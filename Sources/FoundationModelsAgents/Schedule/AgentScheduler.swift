import Foundation
import FoundationModelsExtras
import Logging
import Synchronization
import ULID

/// The weak link from the scheduler to the runner that owns it.
///
/// The runner owns the scheduler, thus the scheduler holds the runner weakly.
final class AgentRunnerReference: Sendable {
    /// The runner, or `nil` after the runner was released.
    private let storage = Mutex<WeakRunner>(WeakRunner())

    /// A weak box of the runner.
    private struct WeakRunner {
        /// The runner.
        weak var runner: AgentRunner?
    }

    /// The runner, or `nil` after it was released.
    var runner: AgentRunner? {
        storage.withLock { $0.runner }
    }

    /// Sets the runner.
    ///
    /// - Parameter runner: The runner.
    func set(_ runner: AgentRunner) {
        storage.withLock { $0.runner = runner }
    }
}

/// What one firing of a task did.
enum AgentScheduleFiring: Sendable, Equatable {
    /// The firing started the run with this id.
    case started(ULID)

    /// The firing did not start a run, because the run of the previous
    /// firing still works.
    case skipped

    /// The firing could not start a run, with the reason. The reason is
    /// mailed to the owner.
    case failed(String)

    /// No task has the id, or the task is ended.
    case notFound
}

/// Fires the scheduled agents of a runner.
///
/// One timer waits for the earliest next firing of the active tasks, at most
/// ``maximumWait`` at a time, thus a change of the system clock is seen. At
/// each wake, each task that is due fires one time: the firings that the
/// wait missed (the computer slept, or the process was down) count as
/// missed, and run once. A task fires only when the run of its previous
/// firing ended; else the firing is skipped and counted.
///
/// A pending task holds no work in its owner session. A firing that runs
/// holds one `childSession` lease in the work registry of its owner, when
/// the owner gave a ``AgentScheduleWorkSite``, from the start of its run to
/// its end.
actor AgentScheduler {
    /// The longest single wait of the timer.
    static let maximumWait: TimeInterval = 60

    /// The most missed firings that one wake counts.
    private static let missedCountLimit = 10_000

    /// The time source.
    let clock: any AgentScheduleClock

    /// The runner that starts each firing.
    private let runnerReference: AgentRunnerReference

    /// The tasks, by id.
    private var tasks: [ULID: AgentScheduledTask] = [:]

    /// The work site of each owner session that gave one.
    private var workSites: [ULID: AgentScheduleWorkSite] = [:]

    /// The open lease of each firing that runs, by task id.
    private var leases: [ULID: BackgroundWork] = [:]

    /// The tasks whose firing is starting a run now.
    private var starting: Set<ULID> = []

    /// The store that saves the tasks of each owner, or `nil`.
    private var store: (any AgentScheduleStore)?

    /// The timer task.
    private var timer: Task<Void, Never>?

    /// `true` after ``stop()``.
    private var isStopped = false

    /// The last firing pass: a tick of the timer or a `start schedule`. Each
    /// pass waits for the one before it, thus two passes never fire the same
    /// task at the same time.
    private var lastPass: Task<Void, Never>?

    /// Makes a scheduler.
    ///
    /// - Parameters:
    ///   - clock: The time source.
    ///   - runnerReference: The link to the runner.
    init(clock: any AgentScheduleClock, runnerReference: AgentRunnerReference) {
        self.clock = clock
        self.runnerReference = runnerReference
    }

    // MARK: - Tasks

    /// Adds a task and starts its timer.
    ///
    /// - Parameters:
    ///   - request: The inputs of the task.
    ///   - workSite: The lease opener of the owner session, or `nil`.
    /// - Returns: The task.
    func add(_ request: AgentScheduleRequest, workSite: AgentScheduleWorkSite?) async -> AgentScheduledTask {
        let task = AgentScheduledTask(request, now: clock.now)
        tasks[task.id] = task
        if let owner = task.owner, let workSite {
            workSites[owner] = workSite
        }
        log(AgentsTelemetry.LogMessage.scheduleCreated, task)
        await persist(owner: task.owner)
        rearm()
        return task
    }

    /// Gives the task with the id `id`.
    ///
    /// - Parameter id: The id of the task.
    /// - Returns: The task, or `nil`.
    func task(id: ULID) -> AgentScheduledTask? {
        tasks[id]
    }

    /// Gives each task of `owner`, oldest first.
    ///
    /// - Parameter owner: The session, or `nil` for the host.
    /// - Returns: The tasks.
    func tasks(owner: ULID?) -> [AgentScheduledTask] {
        tasks.values.filter { $0.owner == owner }.sorted { $0.id < $1.id }
    }

    /// Ends a task. A firing that runs goes on, and its result is mailed.
    ///
    /// - Parameters:
    ///   - id: The id of the task.
    ///   - reason: Why the task ended.
    /// - Returns: The ended task, or `nil` when no task has the id.
    func cancel(id: ULID, reason: String = "it was cancelled") async -> AgentScheduledTask? {
        guard var task = tasks[id] else { return nil }
        if task.state != .ended {
            task.finish(reason)
            tasks[id] = task
            log(AgentsTelemetry.LogMessage.scheduleCancelled, task)
            await persist(owner: task.owner)
            rearm()
        }
        return task
    }

    /// Pauses an active task.
    ///
    /// - Parameter id: The id of the task.
    /// - Returns: The task, or `nil` when no task has the id.
    func pause(id: ULID) async -> AgentScheduledTask? {
        guard var task = tasks[id] else { return nil }
        if task.state == .active {
            task.state = .paused
            tasks[id] = task
            await persist(owner: task.owner)
            rearm()
        }
        return task
    }

    /// Resumes a paused task. Its next firing is the first one after now:
    /// the firings of the pause do not run.
    ///
    /// - Parameter id: The id of the task.
    /// - Returns: The task, or `nil` when no task has the id.
    func resume(id: ULID) async -> AgentScheduledTask? {
        guard var task = tasks[id] else { return nil }
        if task.state == .paused {
            task.state = .active
            task.advance(after: clock.now)
            tasks[id] = task
            await persist(owner: task.owner)
            rearm()
        }
        return task
    }

    /// Ends each task of `owner`, because its session closed, and removes
    /// them.
    ///
    /// - Parameter owner: The session.
    func endTasks(owner: ULID) async {
        let owned = tasks.values.filter { $0.owner == owner }
        for var task in owned {
            if task.state != .ended {
                task.finish("its session closed")
                log(AgentsTelemetry.LogMessage.scheduleCancelled, task)
            }
            tasks[task.id] = nil
        }
        workSites[owner] = nil
        if !owned.isEmpty {
            try? await store?.save([], of: owner)
        }
        rearm()
    }

    /// Stops the timer. The saved tasks stay saved, so that the next process
    /// restores them.
    func stop() {
        isStopped = true
        timer?.cancel()
        timer = nil
    }

    // MARK: - Store

    /// Sets the store that saves the tasks of each owner.
    ///
    /// - Parameter store: The store.
    func use(_ store: any AgentScheduleStore) {
        self.store = store
    }

    /// Restores the saved tasks of `owner`, and starts their timers. A task
    /// that the scheduler holds already is skipped. A firing that was due
    /// while the process was down runs once at the next wake.
    ///
    /// - Parameters:
    ///   - owner: The session.
    ///   - workSite: The lease opener of the owner session, or `nil`.
    /// - Returns: The restored tasks.
    /// - Throws: The error of the store.
    func restore(owner: ULID, workSite: AgentScheduleWorkSite?) async throws -> [AgentScheduledTask] {
        guard let store else { return [] }
        let saved = try await store.load(of: owner)
        var restored: [AgentScheduledTask] = []
        for var task in saved where tasks[task.id] == nil {
            task.liveRunID = nil
            tasks[task.id] = task
            restored.append(task)
        }
        if let workSite {
            workSites[owner] = workSite
        }
        rearm()
        return restored
    }

    /// Saves each task of `owner`.
    ///
    /// - Parameter owner: The session, or `nil` for the host, whose tasks
    ///   are not saved.
    private func persist(owner: ULID?) async {
        guard let owner, let store else { return }
        try? await store.save(tasks(owner: owner), of: owner)
    }

    // MARK: - Firing

    /// Fires each active task that is due at the current time, then sets the
    /// timer again. The pass waits for the pass before it.
    func tick() async {
        await serially { scheduler in await scheduler.fireDueTasks() }
    }

    /// Runs `body` after the pass before it ends.
    ///
    /// - Parameter body: The pass.
    /// - Returns: The value of `body`.
    private func serially<Value: Sendable>(
        _ body: @escaping @Sendable (isolated AgentScheduler) async -> Value
    ) async -> Value {
        let previous = lastPass
        let pass = Task { () -> Value in
            await previous?.value
            return await body(self)
        }
        lastPass = Task { _ = await pass.value }
        return await pass.value
    }

    /// Fires each active task that is due at the current time, then sets the
    /// timer again.
    private func fireDueTasks() async {
        let now = clock.now
        let due = tasks.values.filter { task in
            task.state == .active && (task.nextFiring.map { $0 <= now } ?? false)
        }
        for task in due.sorted(by: { $0.id < $1.id }) {
            _ = await fire(id: task.id, at: now, isManual: false)
        }
        rearm()
    }

    /// Fires one task at `now`.
    ///
    /// - Parameters:
    ///   - id: The id of the task.
    ///   - now: The current time.
    ///   - isManual: `true` for `run schedule`: the firing does not move the
    ///     schedule, and a paused task fires too.
    /// - Returns: What the firing did.
    func fire(id: ULID, at now: Date, isManual: Bool) async -> AgentScheduleFiring {
        guard let snapshot = tasks[id], snapshot.state != .ended, !starting.contains(id) else { return .notFound }
        let missed = isManual ? 0 : missedFirings(of: snapshot, before: now)
        let isLive = await isLive(snapshot)
        // Read the task again: a pause, a resume or a cancel can come during the check.
        guard var task = tasks[id], task.state != .ended else { return .notFound }
        if !isManual {
            task.missedCount += missed
            task.advance(after: now)
        }
        guard !isLive else {
            task.skippedCount += 1
            tasks[id] = task
            log(AgentsTelemetry.LogMessage.scheduleSkipped, task)
            await persist(owner: task.owner)
            return .skipped
        }
        task.runCount += 1
        let number = task.runCount
        tasks[id] = task
        starting.insert(id)
        let start = await startRun(of: task, number: number)
        starting.remove(id)
        guard var current = tasks[id] else { return start }
        switch start {
        case .started:
            log(AgentsTelemetry.LogMessage.scheduleFired, current, firing: number)
        case .failed(let reason):
            current.lastResult = reason
            log(AgentsTelemetry.LogMessage.scheduleFired, current, firing: number, failure: reason)
        case .skipped, .notFound:
            break
        }
        current.endIfDone(at: now)
        tasks[id] = current
        await persist(owner: current.owner)
        return start
    }

    /// Fires one task now, for `run schedule`.
    ///
    /// - Parameter id: The id of the task.
    /// - Returns: What the firing did.
    func runNow(id: ULID) async -> AgentScheduleFiring {
        await serially { scheduler in
            let firing = await scheduler.fire(id: id, at: scheduler.clock.now, isManual: true)
            scheduler.rearm()
            return firing
        }
    }

    /// Counts the firings of `task` after its due time and up to `now`: the
    /// firings that a gap missed.
    ///
    /// - Parameters:
    ///   - task: The task.
    ///   - now: The current time.
    /// - Returns: The count.
    private func missedFirings(of task: AgentScheduledTask, before now: Date) -> Int {
        guard let due = task.nextFiring else { return 0 }
        var count = 0
        var cursor = due
        while count < Self.missedCountLimit,
            let next = task.spec.next(after: cursor, anchor: task.created, timeZone: task.timeZone), next <= now,
            task.end.map({ next <= $0 }) ?? true
        {
            count += 1
            cursor = next
        }
        return count
    }

    /// Tells whether the run of the previous firing of `task` still works.
    ///
    /// - Parameter task: The task.
    /// - Returns: `true` while that run is in operation.
    private func isLive(_ task: AgentScheduledTask) async -> Bool {
        guard let runID = task.liveRunID, let runner = runnerReference.runner else { return false }
        return await runner.run(id: runID)?.state == .running
    }

    /// Starts the run of one firing through the runner, opens its lease, and
    /// watches its end.
    ///
    /// - Parameters:
    ///   - task: The task.
    ///   - number: The number of the firing.
    /// - Returns: What the start did.
    private func startRun(of task: AgentScheduledTask, number: Int) async -> AgentScheduleFiring {
        guard let runner = runnerReference.runner else { return .failed("The agent runner was stopped.") }
        let taskID = task.id
        let header = Self.mailHeader(of: task, firing: number)
        let start = await runner.startFiring(of: task) { [weak self] _, report in
            await self?.record(result: report, of: taskID)
            guard let owner = task.owner else { return }
            let sender = await self?.liveRun(of: taskID) ?? owner
            _ = await runner.mailCaller("\(header)\n\n\(report)", from: sender, to: owner)
        }
        switch start {
        case .started(let run):
            tasks[taskID]?.liveRunID = run.id
            if let owner = task.owner, let workSite = workSites[owner] {
                leases[taskID] = workSite("scheduled-\(run.id)")
            }
            Task { [weak self] in
                _ = try? await run.result()
                await self?.runEnded(run.id, of: taskID)
            }
            return .started(run.id)
        case .failed(let reason):
            if let owner = task.owner {
                _ = await runner.mailCaller("\(header)\n\n\(reason)", from: owner, to: owner)
            }
            return .failed(reason)
        }
    }

    /// Gives the run of the firing of a task that works now.
    ///
    /// - Parameter taskID: The id of the task.
    /// - Returns: The id of the run, or `nil`.
    private func liveRun(of taskID: ULID) -> ULID? {
        tasks[taskID]?.liveRunID
    }

    /// Records the result of the last firing of a task.
    ///
    /// - Parameters:
    ///   - result: The report of the run.
    ///   - taskID: The id of the task.
    private func record(result: String, of taskID: ULID) async {
        guard var task = tasks[taskID] else { return }
        task.lastResult = result
        tasks[taskID] = task
        await persist(owner: task.owner)
    }

    /// Ends the lease of a firing whose run ended, and clears its live run.
    ///
    /// - Parameters:
    ///   - runID: The id of the run.
    ///   - taskID: The id of the task.
    private func runEnded(_ runID: ULID, of taskID: ULID) async {
        leases.removeValue(forKey: taskID)?.end()
        guard var task = tasks[taskID], task.liveRunID == runID else { return }
        task.liveRunID = nil
        tasks[taskID] = task
        await persist(owner: task.owner)
    }

    /// The first line of the mail of each firing: the task, its id and the
    /// number of the firing.
    ///
    /// - Parameters:
    ///   - task: The task.
    ///   - number: The number of the firing.
    /// - Returns: The line.
    static func mailHeader(of task: AgentScheduledTask, firing number: Int) -> String {
        "Scheduled task \"\(task.name)\" (\(task.id)), firing \(number), agent \(task.agent):"
    }

    // MARK: - Timer

    /// Sets the timer to the earliest next firing of the active tasks, at
    /// most ``maximumWait`` from now.
    private func rearm() {
        timer?.cancel()
        timer = nil
        guard !isStopped,
            let earliest = tasks.values.filter({ $0.state == .active }).compactMap(\.nextFiring).min()
        else {
            return
        }
        let clock = clock
        let deadline = min(earliest, clock.now.addingTimeInterval(Self.maximumWait))
        timer = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.tick()
        }
    }

    // MARK: - Telemetry

    /// Writes one record of a task.
    ///
    /// - Parameters:
    ///   - message: The message.
    ///   - task: The task.
    ///   - firing: The number of the firing, or `nil`.
    ///   - failure: The reason of a failed firing, or `nil`.
    private func log(
        _ message: String, _ task: AgentScheduledTask, firing: Int? = nil, failure: String? = nil
    ) {
        guard let runner = runnerReference.runner else { return }
        var metadata: Logger.Metadata = [
            AgentsTelemetry.LogMetadataKey.scheduleID: .string(task.id.description),
            AgentsTelemetry.LogMetadataKey.agentName: .string(task.agent),
            AgentsTelemetry.LogMetadataKey.schedule: .string(task.schedule),
            AgentsTelemetry.LogMetadataKey.scheduleState: .string(task.state.rawValue)
        ]
        if let owner = task.owner {
            metadata[AgentsTelemetry.LogMetadataKey.callerSessionID] = .string(owner.description)
        }
        if let firing {
            metadata[AgentsTelemetry.LogMetadataKey.scheduleFiring] = .stringConvertible(firing)
        }
        if let runID = task.liveRunID {
            metadata[AgentsTelemetry.LogMetadataKey.runID] = .string(runID.description)
        }
        if let failure {
            metadata[AgentsTelemetry.LogMetadataKey.scheduleFailure] = .string(failure)
        }
        runner.environment.makeRunLogger().info("\(message)", metadata: metadata)
    }
}
