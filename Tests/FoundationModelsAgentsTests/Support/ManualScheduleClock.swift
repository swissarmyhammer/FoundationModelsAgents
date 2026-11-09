import Foundation
@testable import FoundationModelsAgents
import Synchronization

/// A schedule clock that moves only when a test calls ``advance(by:)``.
///
/// A wait ends when an advance reaches its deadline, or with
/// `CancellationError` when its task is cancelled.
final class ManualScheduleClock: AgentScheduleClock, Sendable {
    /// One wait.
    private struct Sleeper {
        /// The time to wake.
        let deadline: Date

        /// The wait.
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// The state of the clock.
    private struct State {
        /// The current time.
        var now: Date

        /// The waits, by id.
        var sleepers: [UUID: Sleeper] = [:]
    }

    /// The state.
    private let state: Mutex<State>

    /// Makes a clock at `start`.
    ///
    /// - Parameter start: The first time.
    init(start: Date) {
        state = Mutex(State(now: start))
    }

    /// The current time.
    var now: Date {
        state.withLock { $0.now }
    }

    /// The count of the waits that have not ended.
    var sleeperCount: Int {
        state.withLock { $0.sleepers.count }
    }

    /// Waits until an advance reaches `deadline`.
    ///
    /// - Parameter deadline: The time to wake.
    /// - Throws: `CancellationError` when the task is cancelled.
    func sleep(until deadline: Date) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let isDue = state.withLock { state in
                    guard deadline > state.now, !Task.isCancelled else { return true }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return false
                }
                if isDue {
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume()
                    }
                }
            }
        } onCancel: {
            state.withLock { $0.sleepers.removeValue(forKey: id) }?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves the clock forward, and wakes each wait whose deadline is
    /// reached.
    ///
    /// - Parameter seconds: The seconds to move.
    func advance(by seconds: TimeInterval) {
        let woken = state.withLock { state in
            state.now = state.now.addingTimeInterval(seconds)
            let now = state.now
            let due = state.sleepers.filter { $0.value.deadline <= now }
            for id in due.keys {
                state.sleepers[id] = nil
            }
            return due.values.map(\.continuation)
        }
        for continuation in woken {
            continuation.resume()
        }
    }
}
