import Foundation
import Synchronization

/// A signal that fires one time, and the tests that wait for it.
private struct ScriptedGateSignal {
    /// The continuation of one test that waits for the signal.
    typealias Watcher = CheckedContinuation<Void, Never>

    /// `true` after the signal fired.
    private var hasFired = false

    /// The tests that wait for the signal.
    private var watchers: [Watcher] = []

    /// Fires the signal.
    ///
    /// - Returns: The watchers to resume, outside the lock.
    mutating func fire() -> [Watcher] {
        hasFired = true
        let released = watchers
        watchers.removeAll()
        return released
    }

    /// Adds `watcher` when the signal did not fire yet.
    ///
    /// - Parameter watcher: The continuation of a test that waits.
    /// - Returns: `true` when the signal already fired. The caller then
    ///   resumes `watcher` at once, outside the lock.
    mutating func watch(_ watcher: Watcher) -> Bool {
        if !hasFired {
            watchers.append(watcher)
        }
        return hasFired
    }
}

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
/// A ``ScriptedAgentStep/holdThroughCancel(_:)`` step calls
/// ``waitThroughCancel()`` in place of ``wait()``. A cancel does not release
/// that call: the gate records the cancel, and the call returns only when
/// the gate opens. The test calls ``waitForCancel()`` to know that the
/// cancel arrived.
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

        /// Fires when the first wait call arrives.
        var arrival = ScriptedGateSignal()

        /// Fires when the task of a ``ScriptedGate/waitThroughCancel()``
        /// call is cancelled.
        var cancel = ScriptedGateSignal()
    }

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

    /// Holds the caller until the gate opens, also when the task of the
    /// caller is cancelled. A cancel fires the signal that
    /// ``waitForCancel()`` waits for.
    func waitThroughCancel() async {
        await withTaskCancellationHandler {
            // No cancel handler releases this new id, thus the hold ends
            // only when the gate opens, and it never throws.
            try? await withCheckedThrowingContinuation { continuation in
                hold(continuation, id: UUID())
            }
        } onCancel: {
            resume(state.withLock { $0.cancel.fire() })
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

    /// Holds the caller until a wait call arrives at the gate.
    ///
    /// Returns at once when a call already arrived.
    func waitForArrival() async {
        await withCheckedContinuation { continuation in
            if state.withLock({ $0.arrival.watch(continuation) }) {
                continuation.resume()
            }
        }
    }

    /// Holds the caller until the task of a ``waitThroughCancel()`` call is
    /// cancelled.
    ///
    /// Returns at once when a cancel already arrived.
    func waitForCancel() async {
        await withCheckedContinuation { continuation in
            if state.withLock({ $0.cancel.watch(continuation) }) {
                continuation.resume()
            }
        }
    }

    /// Holds `continuation` until the gate opens, or resumes it at once.
    ///
    /// - Parameters:
    ///   - continuation: The continuation of one ``wait()`` or
    ///     ``waitThroughCancel()`` call.
    ///   - id: The id of that call.
    private func hold(_ continuation: CheckedContinuation<Void, any Error>, id: UUID) {
        let (outcome, watchers) = state.withLock { state -> (Result<Void, any Error>?, [ScriptedGateSignal.Watcher]) in
            let watchers = state.arrival.fire()
            if state.cancelledBeforeHold.remove(id) != nil {
                return (.failure(CancellationError()), watchers)
            }
            if state.isOpen {
                return (.success(()), watchers)
            }
            state.waiters[id] = continuation
            return (nil, watchers)
        }
        resume(watchers)
        if let outcome {
            continuation.resume(with: outcome)
        }
    }

    /// Resumes each watcher of a signal that fired.
    ///
    /// - Parameter watchers: The watchers that the signal released.
    private func resume(_ watchers: [ScriptedGateSignal.Watcher]) {
        for watcher in watchers {
            watcher.resume()
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
