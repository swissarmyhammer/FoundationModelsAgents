import Foundation
import Synchronization
import ULID

/// The state of one run at one time, in values that a host can keep and compare.
public struct AgentRunSnapshot: Sendable, Equatable {
    /// What a run does now.
    public enum Status: Sendable, Equatable {
        /// The run answers its task or a message.
        case working

        /// The run answered its task and waits for the runs that it started.
        case waitingForChildren

        /// The Router holds the mail of the run. The text tells why.
        case paused(String)

        /// The run ended with its final answer.
        case finished

        /// The run ended with an error. The text tells why.
        case failed(String)

        /// The run ended because of a cancel.
        case cancelled

        /// `true` while the run is in operation: working, waiting for children, or paused.
        public var isRunning: Bool {
            switch self {
            case .working, .waitingForChildren, .paused: true
            case .finished, .failed, .cancelled: false
            }
        }
    }

    /// The id of the run, which is the id of its session.
    public let id: ULID

    /// The id of the agent in the catalog.
    public let agentID: String

    /// The name of the agent. It is the id, because an agent has no other name.
    public let agentName: String

    /// The `description` of the agent, or `nil`.
    public let agentDescription: String?

    /// The session that started the run, or `nil` for a run that the host started.
    public let callerSession: ULID?

    /// The run of the session that started this run, or `nil` when the caller is not a run.
    public let parentRunID: ULID?

    /// The depth of the run. A host-started run has depth one.
    public let depth: Int

    /// The completion token of the `start agent` call that started the run, or `nil`.
    public let completionToken: String?

    /// The working folder of the run, or `nil` when the setup of the run failed.
    public let workingDirectory: URL?

    /// What the run does now.
    public let status: Status

    /// The progress text of the run: what it did last.
    public let progress: String
}

/// Sends the snapshots of the runs of one runner to its subscribers.
///
/// A `Mutex` guards the subscribers, and every snapshot is made under that lock, thus a
/// subscriber gets the states of a run in the order they happened.
final class RunChangeHub: Sendable {
    private struct State {
        var subscribers: [UUID: AsyncStream<AgentRunSnapshot>.Continuation] = [:]
        var isFinished = false
    }

    private let state = Mutex(State())

    /// Adds a subscriber. Its stream starts with the current snapshot of each run in `runs`.
    ///
    /// - Parameter runs: The runs in operation.
    /// - Returns: The stream. It is finished at once after ``finish()``.
    func subscribe(starting runs: [AgentRun]) -> AsyncStream<AgentRunSnapshot> {
        let (stream, continuation) = AsyncStream<AgentRunSnapshot>.makeStream()
        let key = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { $0.subscribers[key] = nil }
        }
        let isFinished = state.withLock { state -> Bool in
            guard !state.isFinished else { return true }
            for run in runs {
                continuation.yield(run.snapshot)
            }
            state.subscribers[key] = continuation
            return false
        }
        if isFinished {
            continuation.finish()
        }
        return stream
    }

    /// Sends the snapshot of `run` to each subscriber.
    func publish(_ run: AgentRun) {
        state.withLock { state in
            guard !state.subscribers.isEmpty else { return }
            let snapshot = run.snapshot
            for continuation in state.subscribers.values {
                continuation.yield(snapshot)
            }
        }
    }

    /// Finishes each stream.
    func finish() {
        // The finish calls `onTermination`, which takes the lock, thus it runs after the lock ends.
        let continuations = state.withLock { state in
            state.isFinished = true
            defer { state.subscribers = [:] }
            return Array(state.subscribers.values)
        }
        for continuation in continuations {
            continuation.finish()
        }
    }
}

extension AgentRun {
    /// The state of the run now.
    public var snapshot: AgentRunSnapshot {
        AgentRunSnapshot(
            id: id, agentID: agent.id, agentName: agent.id, agentDescription: agent.description,
            callerSession: caller, parentRunID: parentRunID, depth: depth, completionToken: completionToken,
            workingDirectory: workingDirectory, status: status, progress: progress.text)
    }

    /// The status of the run, from its state, its phase, and its pause.
    var status: AgentRunSnapshot.Status {
        switch state {
        case .finished: .finished
        case .failed(let failure): .failed(failure.reason)
        case .cancelled: .cancelled
        case .running:
            if let pause = pauseDescription {
                .paused(pause)
            } else if phase == .waitingForChildren {
                .waitingForChildren
            } else {
                .working
            }
        }
    }
}

extension AgentRunner {
    /// The snapshots of the runs in operation and of the retained records of finished runs.
    ///
    /// - Returns: One snapshot for each run, in id order.
    public func snapshots() -> [AgentRunSnapshot] {
        retireEndedRuns()
        return (Array(openRuns.values) + records).sorted { $0.id < $1.id }.map(\.snapshot)
    }

    /// A stream of the state changes of the runs of this runner.
    ///
    /// The stream starts with the current snapshot of each run in operation, thus a late
    /// subscriber misses nothing. After that it gives one snapshot for each change of the status
    /// of a run, not one for each event of a session. The stream finishes at ``stop()``.
    ///
    /// - Returns: The stream.
    public func runChanges() -> AsyncStream<AgentRunSnapshot> {
        retireEndedRuns()
        return changeHub.subscribe(starting: openRuns.values.sorted { $0.id < $1.id })
    }
}
