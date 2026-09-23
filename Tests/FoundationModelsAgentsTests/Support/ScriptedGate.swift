import Foundation
import Synchronization

/// A gate that holds a scripted step until a test opens it.
///
/// A ``ScriptedAgentStep/wait(_:)`` step calls ``wait()``. The turn then
/// stays in the step until the test calls ``open()``. The test calls
/// ``waitForArrival()`` first, to know that the turn is in the step.
///
/// The gate opens one time and stays open. A ``wait()`` after ``open()``
/// returns at once. A cancelled waiter throws `CancellationError`, thus a
/// test can cancel a held turn.
///
/// A class, because the script and the test hold the same gate. A `Mutex`
/// guards the state, thus the `Sendable` conformance is compiler-checked.
final class ScriptedGate: Sendable {
    /// The state that the lock guards.
    private struct State {
        /// `true` after ``ScriptedGate/open()``.
        var isOpen = false

        /// The held waiters, by the id of each ``ScriptedGate/wait()`` call.
        var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

        /// The ids of the ``ScriptedGate/wait()`` calls whose task was
        /// cancelled before the call held its continuation.
        var cancelledBeforeHold: Set<UUID> = []

        /// `true` after the first ``ScriptedGate/wait()`` call arrived.
        var hasArrival = false

        /// The tests that wait for the first arrival.
        var arrivalWatchers: [ArrivalWatcher] = []
    }

    /// The continuation of one ``waitForArrival()`` call.
    private typealias ArrivalWatcher = CheckedContinuation<Void, Never>

    /// The state of the gate.
    private let state = Mutex(State())

    /// Makes a closed gate.
    init() {}

    /// Holds the caller until the gate opens.
    ///
    /// - Throws: `CancellationError` when the task of the caller is cancelled
    ///   before the gate opens.
    func wait() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                hold(continuation, id: id)
            }
        } onCancel: {
            release(id: id)
        }
    }

    /// Opens the gate, and releases each held waiter.
    func open() {
        let released = state.withLock { state in
            state.isOpen = true
            let waiters = Array(state.waiters.values)
            state.waiters.removeAll()
            return waiters
        }
        for waiter in released {
            waiter.resume()
        }
    }

    /// Holds the caller until a ``wait()`` call arrives at the gate.
    ///
    /// Returns at once when a call already arrived.
    func waitForArrival() async {
        await withCheckedContinuation { continuation in
            let hasArrival = state.withLock { state in
                if !state.hasArrival {
                    state.arrivalWatchers.append(continuation)
                }
                return state.hasArrival
            }
            if hasArrival {
                continuation.resume()
            }
        }
    }

    /// Holds `continuation` until the gate opens, or resumes it at once.
    ///
    /// - Parameters:
    ///   - continuation: The continuation of one ``wait()`` call.
    ///   - id: The id of that call.
    private func hold(_ continuation: CheckedContinuation<Void, any Error>, id: UUID) {
        let (outcome, watchers) = state.withLock { state -> (Result<Void, any Error>?, [ArrivalWatcher]) in
            let watchers = state.arrivalWatchers
            state.arrivalWatchers.removeAll()
            state.hasArrival = true
            if state.cancelledBeforeHold.remove(id) != nil {
                return (.failure(CancellationError()), watchers)
            }
            if state.isOpen {
                return (.success(()), watchers)
            }
            state.waiters[id] = continuation
            return (nil, watchers)
        }
        for watcher in watchers {
            watcher.resume()
        }
        if let outcome {
            continuation.resume(with: outcome)
        }
    }

    /// Releases the held ``wait()`` call `id` with `CancellationError`.
    ///
    /// When the call does not hold its continuation yet, the gate records
    /// the id, and ``hold(_:id:)`` then resumes the call at once.
    ///
    /// - Parameter id: The id of the cancelled call.
    private func release(id: UUID) {
        let waiter = state.withLock { state in
            let waiter = state.waiters.removeValue(forKey: id)
            if waiter == nil {
                state.cancelledBeforeHold.insert(id)
            }
            return waiter
        }
        waiter?.resume(throwing: CancellationError())
    }
}
