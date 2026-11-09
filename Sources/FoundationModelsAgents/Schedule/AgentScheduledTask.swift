import Foundation
import FoundationModelsExtras
import ULID

/// One scheduled agent: an agent, a prompt and a schedule. Each firing is a
/// child run of the session that made the task, and its result is mailed to
/// that session.
public struct AgentScheduledTask: Sendable, Equatable, Codable {
    /// The state of a task.
    public enum State: String, Sendable, Codable {
        /// The task fires on its schedule.
        case active

        /// The task does not fire until it is resumed.
        case paused

        /// The task does not fire again.
        case ended
    }

    /// The default time that a recurring task with no `until` and no `count`
    /// lives: 7 days.
    public static let defaultLifetime: TimeInterval = 7 * 24 * 60 * 60

    /// The id of the task.
    public let id: ULID

    /// The name of the task: the name that the creator gave, or the agent
    /// and the schedule.
    public let name: String

    /// The id of the agent of each firing.
    public let agent: String

    /// The task prompt of each firing.
    public let prompt: String

    /// When the task fires.
    public let spec: AgentScheduleSpec

    /// The English text that the normalizer read, or `nil` for a direct form.
    public let english: String?

    /// The identifier of the time zone of the task.
    public let timeZoneIdentifier: String

    /// The session that made the task, and that gets the result of each
    /// firing, or `nil` for the host.
    public let owner: ULID?

    /// The working folder of each firing, or `nil` for the folder of the
    /// owner.
    public let workingDirectory: URL?

    /// The time that the task was made. An interval counts from it.
    public let created: Date

    /// The time after which the task does not fire, or `nil` for none.
    public let end: Date?

    /// The most firings, or `nil` for no count.
    public let maxRuns: Int?

    /// The state of the task.
    public internal(set) var state: State = .active

    /// Why the task ended, or `nil` while it has not ended.
    public internal(set) var endReason: String?

    /// The time of the next firing, or `nil` when the task does not fire
    /// again.
    public internal(set) var nextFiring: Date?

    /// The count of firings that started a run.
    public internal(set) var runCount = 0

    /// The count of firings that were skipped, because the run of the
    /// previous firing was still working.
    public internal(set) var skippedCount = 0

    /// The count of firings that were missed while the process slept or was
    /// down. The missed firings of one gap run one time.
    public internal(set) var missedCount = 0

    /// The result of the last firing that ended, or `nil` before the first.
    public internal(set) var lastResult: String?

    /// The run of the firing that works now, or `nil`.
    public internal(set) var liveRunID: ULID?

    /// The time zone of the task.
    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    /// The normalized schedule text.
    public var schedule: String {
        spec.normalized(timeZone: timeZone)
    }

    /// Makes a task from a request, at `now`.
    ///
    /// - Parameters:
    ///   - request: The request.
    ///   - now: The current time.
    init(_ request: AgentScheduleRequest, now: Date) {
        id = ULID()
        agent = request.agent
        prompt = request.prompt
        spec = request.spec
        english = request.english
        timeZoneIdentifier = request.timeZone.identifier
        owner = request.owner
        workingDirectory = request.workingDirectory
        created = now
        let givenName = request.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        name = givenName.isEmpty
            ? "\(request.agent) \(request.spec.normalized(timeZone: request.timeZone))" : givenName
        if request.spec.isRecurring {
            end = request.until ?? (request.count == nil ? now.addingTimeInterval(Self.defaultLifetime) : nil)
            maxRuns = request.count
        } else {
            end = nil
            maxRuns = nil
        }
        nextFiring = spec.next(after: now, anchor: now, timeZone: request.timeZone)
        endIfDone(at: now)
    }

    /// The next firings after `date`, at most `count`, within the end and
    /// the count of the task.
    ///
    /// - Parameters:
    ///   - date: The time to search after.
    ///   - count: The most firings.
    /// - Returns: The times.
    public func upcoming(after date: Date, count: Int) -> [Date] {
        guard state != .ended else { return [] }
        let left = maxRuns.map { max(0, $0 - runCount) } ?? count
        return spec.firings(after: date, anchor: created, timeZone: timeZone, count: min(count, left))
            .filter { time in end.map { time <= $0 } ?? true }
    }

    /// Sets the next firing after `date`, and ends the task when it has no
    /// next firing.
    ///
    /// - Parameter date: The time to search after.
    mutating func advance(after date: Date) {
        nextFiring = spec.next(after: date, anchor: created, timeZone: timeZone)
        endIfDone(at: date)
    }

    /// Ends the task when its count is used, or when its next firing is past
    /// its end or missing.
    ///
    /// - Parameter date: The current time.
    mutating func endIfDone(at date: Date) {
        guard state != .ended else { return }
        if let maxRuns, runCount >= maxRuns {
            finish("it ran \(maxRuns) time\(maxRuns == 1 ? "" : "s")")
        } else if let end, let next = nextFiring, next > end {
            finish("it reached its end, \(AgentScheduleSpec.formatted(end, in: timeZone))")
        } else if nextFiring == nil {
            finish(spec.isRecurring ? "its schedule has no next firing" : "it ran its one time")
        }
    }

    /// Ends the task.
    ///
    /// - Parameter reason: Why it ended.
    mutating func finish(_ reason: String) {
        state = .ended
        endReason = reason
        nextFiring = nil
    }
}

/// The inputs of a new scheduled agent.
public struct AgentScheduleRequest: Sendable {
    /// The id of the agent of each firing.
    public var agent: String

    /// The task prompt of each firing.
    public var prompt: String

    /// When the task fires.
    public var spec: AgentScheduleSpec

    /// The English text that the normalizer read, or `nil`.
    public var english: String?

    /// The time zone of the task.
    public var timeZone: TimeZone

    /// The time after which a recurring task does not fire, or `nil`.
    public var until: Date?

    /// The most firings of a recurring task, or `nil`.
    public var count: Int?

    /// The name of the task, or `nil` for a made name.
    public var name: String?

    /// The session that gets the result of each firing, or `nil` for the
    /// host.
    public var owner: ULID?

    /// The working folder of each firing, or `nil` for the folder of the
    /// owner.
    public var workingDirectory: URL?

    /// Makes a request.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent.
    ///   - prompt: The task prompt of each firing.
    ///   - spec: When the task fires.
    ///   - english: The English text that the normalizer read, or `nil`.
    ///   - timeZone: The time zone of the task.
    ///   - until: The end of a recurring task, or `nil`.
    ///   - count: The most firings of a recurring task, or `nil`.
    ///   - name: The name, or `nil`.
    ///   - owner: The session that gets each result, or `nil`.
    ///   - workingDirectory: The folder of each firing, or `nil`.
    public init(
        agent: String = AgentCatalog.defaultAgentID, prompt: String, spec: AgentScheduleSpec, english: String? = nil,
        timeZone: TimeZone = .current, until: Date? = nil, count: Int? = nil, name: String? = nil,
        owner: ULID? = nil, workingDirectory: URL? = nil
    ) {
        self.agent = agent
        self.prompt = prompt
        self.spec = spec
        self.english = english
        self.timeZone = timeZone
        self.until = until
        self.count = count
        self.name = name
        self.owner = owner
        self.workingDirectory = workingDirectory
    }
}

/// Opens the `childSession` lease of one firing in the work registry of the
/// owner session. The argument is the id of the lease.
public typealias AgentScheduleWorkSite = @Sendable (String) -> BackgroundWork

/// The time source of the scheduler.
public protocol AgentScheduleClock: Sendable {
    /// The current time.
    var now: Date { get }

    /// Waits until `deadline`.
    ///
    /// - Parameter deadline: The time to wake.
    /// - Throws: `CancellationError` when the task is cancelled.
    func sleep(until deadline: Date) async throws
}

/// The clock of the system. A wait counts the time that the computer
/// sleeps, thus a firing that was due in the sleep runs on wake.
public struct SystemScheduleClock: AgentScheduleClock {
    /// Makes the clock.
    public init() {}

    /// The current time.
    public var now: Date { Date() }

    /// Waits until `deadline` on the continuous clock.
    ///
    /// - Parameter deadline: The time to wake.
    /// - Throws: `CancellationError` when the task is cancelled.
    public func sleep(until deadline: Date) async throws {
        let seconds = max(0, deadline.timeIntervalSinceNow)
        try await Task.sleep(for: .seconds(seconds), clock: .continuous)
    }
}

/// Saves the scheduled agents of each session, so that a restart or a resume
/// of the session restores them.
public protocol AgentScheduleStore: Sendable {
    /// Saves each task of the session `owner`, in place of its saved tasks.
    ///
    /// - Parameters:
    ///   - tasks: The tasks. An empty list removes the saved tasks.
    ///   - owner: The session.
    /// - Throws: The error of the store.
    func save(_ tasks: [AgentScheduledTask], of owner: ULID) async throws

    /// Reads the saved tasks of the session `owner`.
    ///
    /// - Parameter owner: The session.
    /// - Returns: The tasks, or none.
    /// - Throws: The error of the store.
    func load(of owner: ULID) async throws -> [AgentScheduledTask]
}
