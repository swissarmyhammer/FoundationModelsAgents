import Foundation
import ULID

/// What the runner did with one firing of a scheduled agent.
enum AgentFiringStart: Sendable {
    /// The firing started this run.
    case started(AgentRun)

    /// The firing started no run, with the reason.
    case failed(String)
}

extension AgentRunner {
    // MARK: - Scheduled agents

    /// Adds a scheduled agent. Each firing is a child run of
    /// ``AgentScheduleRequest/owner``, and its result is mailed to that
    /// session after each firing.
    ///
    /// - Parameters:
    ///   - request: The inputs of the task.
    ///   - workSite: Opens the `childSession` lease of a firing in the work
    ///     registry of the owner, or `nil` for no lease. A pending task holds
    ///     no lease.
    /// - Returns: The task.
    public func schedule(
        _ request: AgentScheduleRequest, workSite: AgentScheduleWorkSite? = nil
    ) async -> AgentScheduledTask {
        await scheduler.add(request, workSite: workSite)
    }

    /// Gives the scheduled agent with the id `id`.
    ///
    /// - Parameter id: The id of the task.
    /// - Returns: The task, or `nil`.
    public func scheduledTask(id: ULID) async -> AgentScheduledTask? {
        await scheduler.task(id: id)
    }

    /// Gives each scheduled agent of one session, oldest first.
    ///
    /// - Parameter owner: The session, or `nil` for the host.
    /// - Returns: The tasks.
    public func scheduledTasks(owner: ULID?) async -> [AgentScheduledTask] {
        await scheduler.tasks(owner: owner)
    }

    /// Ends a scheduled agent. A firing that runs goes on.
    ///
    /// - Parameter id: The id of the task.
    /// - Returns: The ended task, or `nil` when no task has the id.
    @discardableResult
    public func cancelSchedule(id: ULID) async -> AgentScheduledTask? {
        await scheduler.cancel(id: id)
    }

    /// Pauses a scheduled agent.
    ///
    /// - Parameter id: The id of the task.
    /// - Returns: The task, or `nil` when no task has the id.
    @discardableResult
    public func pauseSchedule(id: ULID) async -> AgentScheduledTask? {
        await scheduler.pause(id: id)
    }

    /// Resumes a paused scheduled agent. The firings of the pause do not run.
    ///
    /// - Parameter id: The id of the task.
    /// - Returns: The task, or `nil` when no task has the id.
    @discardableResult
    public func resumeSchedule(id: ULID) async -> AgentScheduledTask? {
        await scheduler.resume(id: id)
    }

    /// Sets the store that saves the scheduled agents of each session.
    ///
    /// - Parameter store: The store.
    public func useScheduleStore(_ store: any AgentScheduleStore) async {
        await scheduler.use(store)
    }

    /// Restores the saved scheduled agents of the session `owner` after a
    /// restart or a resume, and starts their timers. A firing that was due
    /// while the process was down runs once.
    ///
    /// - Parameters:
    ///   - owner: The session.
    ///   - workSite: Opens the lease of a firing in the work registry of the
    ///     session, or `nil`.
    /// - Returns: The restored tasks.
    /// - Throws: The error of the store.
    public func restoreSchedules(
        of owner: ULID, workSite: AgentScheduleWorkSite? = nil
    ) async throws -> [AgentScheduledTask] {
        try await scheduler.restore(owner: owner, workSite: workSite)
    }

    /// Starts the run of one firing of `task`: a child run of the owner of
    /// the task, with the mail route to it.
    ///
    /// The definition of the agent is read from the current catalog, thus a
    /// reload changes the next firing. The default agent can fire, though the
    /// `agents` tool never starts it. The run has the depth, the slot and the
    /// folder that a `start agent` call of the owner gives its child, and it
    /// counts against ``AgentEnvironment/maxConcurrentAgents``.
    ///
    /// - Parameters:
    ///   - task: The task.
    ///   - resultMail: Gets the final state and the report of the run.
    /// - Returns: The run, or the reason that no run started.
    func startFiring(
        of task: AgentScheduledTask, resultMail: @escaping @Sendable (AgentRunState, String) async -> Void
    ) async -> AgentFiringStart {
        guard let definition = registry.catalog().definition(named: task.agent) else {
            let available = registry.catalog().modelVisible.map(\.id)
            return .failed(AgentsToolText.unknownAgent(task.agent, available: available))
        }
        retireEndedRuns()
        let ownerRun = task.owner.flatMap { openRuns[$0] }
        let depth = ownerRun.map { $0.depth + 1 } ?? Self.hostDepth
        guard depth <= environment.maxDepth else {
            return .failed(AgentsToolText.atDepthLimit(maxDepth: environment.maxDepth))
        }
        var request = AgentRunRequest(
            definition: definition, prompt: task.prompt, context: nil,
            inheritedSlot: ownerRun?.parentRun?.slot ?? environment.defaultSlot, depth: depth,
            parent: ownerRun?.parentRun, agentsTool: AgentRun.agentsTool(of: self),
            requestedDirectory: task.workingDirectory)
        request.restoredCaller = task.owner
        request.resultMail = resultMail
        switch await startWithinLimit(request) {
        case .atLimit(let working):
            return .failed(AgentsToolText.atLimit(working: working))
        case .stopped:
            return .failed(AgentsToolText.stopped)
        case .started(let run):
            guard !run.isSetupFailure else {
                return .failed(run.report)
            }
            return .started(run)
        }
    }
}

