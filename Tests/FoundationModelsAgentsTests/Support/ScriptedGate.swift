import Foundation
import Synchronization

@testable import FoundationModelsAgents

/// A signal that fires one time, and the tests that wait for it.
private struct ScriptedGateSignal {
    /// The continuation of one test that waits for the signal.
    typealias Watcher = CheckedContinuation<Void, Never>

    /// `true` after the signal fired.
    private(set) var hasFired = false

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

/// The waiters that the first wait call at a ``ScriptedGate`` releases. The
/// gate resumes them outside its lock.
private struct ScriptedGateArrival {
    /// The watchers of ``ScriptedGate/waitForArrival()``.
    let watchers: [ScriptedGateSignal.Watcher]

    /// The watchers of ``ScriptedGate/waitForArrival(orEndOf:)``.
    let runWatchers: [CheckedContinuation<Bool, Never>]

    /// Resumes each watcher: a run watcher with `true`, because a call
    /// arrived.
    func resume() {
        for watcher in watchers {
            watcher.resume()
        }
        for watcher in runWatchers {
            watcher.resume(returning: true)
        }
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

        /// Each test that waits in ``ScriptedGate/waitForArrival(orEndOf:)``,
        /// by the id of its wait.
        var runWatchers: [UUID: CheckedContinuation<Bool, Never>] = [:]

        /// The id of each ``ScriptedGate/waitForArrival(orEndOf:)`` wait
        /// whose run or task ended before the wait held its continuation.
        var endedRunWaits: Set<UUID> = []

        /// Fires when the task of a ``ScriptedGate/waitThroughCancel()``
        /// call is cancelled.
        var cancel = ScriptedGateSignal()

        /// Fires the arrival signal, and takes each run watcher.
        ///
        /// - Returns: The waiters to resume, outside the lock.
        mutating func arrive() -> ScriptedGateArrival {
            defer { runWatchers.removeAll() }
            return ScriptedGateArrival(watchers: arrival.fire(), runWatchers: Array(runWatchers.values))
        }
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

    /// Holds the caller until the gate opens, or until `run` ends. The end of
    /// `run` opens the gate. Thus a run that fails before the event that
    /// opens the gate cannot make the test wait for ever.
    ///
    /// Use it only for a gate that the test or a run event observer opens,
    /// not for the gate of a scripted step: the end of `run` releases each
    /// waiter of the gate.
    ///
    /// The wait starts a task that waits for the final state of `run`. That
    /// task does not cancel the run, and it ends when the run ends.
    ///
    /// - Parameter run: The run whose end also opens the gate.
    /// - Throws: `CancellationError` when the task of the caller is cancelled
    ///   before the gate opens.
    func wait(orEndOf run: AgentRun) async throws {
        Task {
            _ = await run.finalState()
            self.open()
        }
        try await wait()
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

    /// Holds the caller until a wait call arrives at the gate, or until `run`
    /// ends. Thus a run that fails before it arrives at the gate cannot make
    /// the test wait for ever.
    ///
    /// The wait starts a task that waits for the final state of `run`. That
    /// task does not cancel the run, and it ends when the run ends.
    ///
    /// - Parameter run: The run that must arrive at the gate, or start the
    ///   run that arrives at the gate.
    /// - Returns: `true` when a wait call arrived, `false` when `run` ended
    ///   first.
    func waitForArrival(orEndOf run: AgentRun) async -> Bool {
        await waitForArrival(orEnd: { _ = await run.finalState() })
    }

    /// Holds the caller until a wait call arrives at the gate, or until
    /// `task` ends. Thus a task that fails before it arrives at the gate
    /// cannot make the test wait for ever.
    ///
    /// Use it when the test has no ``AgentRun`` before the wait: for example a
    /// turn of a session, or a reader that starts its run itself.
    ///
    /// The wait starts a task that waits for the result of `task`. That task
    /// does not cancel `task`, and it ends when `task` ends.
    ///
    /// - Parameter task: The task that must arrive at the gate, or start the
    ///   run that arrives at the gate.
    /// - Returns: `true` when a wait call arrived, `false` when `task` ended
    ///   first.
    func waitForArrival<Success: Sendable, Failure: Error>(orEndOf task: Task<Success, Failure>) async -> Bool {
        await waitForArrival(orEnd: { _ = await task.result })
    }

    /// Holds the caller until a wait call arrives at the gate, or until `end`
    /// returns.
    ///
    /// The wait starts a task that calls `end`.
    ///
    /// - Parameter end: Returns when the work that must arrive at the gate
    ///   ended.
    /// - Returns: `true` when a wait call arrived, `false` when `end` returned
    ///   first.
    private func waitForArrival(orEnd end: @escaping @Sendable () async -> Void) async -> Bool {
        let id = UUID()
        Task {
            await end()
            self.endRunWait(id)
        }
        return await withCheckedContinuation { continuation in
            let answer: Bool? = state.withLock { state in
                if state.arrival.hasFired { return true }
                if state.endedRunWaits.remove(id) != nil { return false }
                state.runWatchers[id] = continuation
                return nil
            }
            if let answer {
                continuation.resume(returning: answer)
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
        let (outcome, arrival) = state.withLock { state -> (Result<Void, any Error>?, ScriptedGateArrival) in
            let arrival = state.arrive()
            if state.cancelledBeforeHold.remove(id) != nil {
                return (.failure(CancellationError()), arrival)
            }
            if state.isOpen {
                return (.success(()), arrival)
            }
            state.waiters[id] = continuation
            return (nil, arrival)
        }
        arrival.resume()
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

    /// Ends the ``waitForArrival(orEndOf:)`` wait `id` with `false`, because
    /// its run or task ended. When the wait does not hold its continuation
    /// yet, the gate records the id, and the wait then ends at once.
    ///
    /// - Parameter id: The id of the wait.
    private func endRunWait(_ id: UUID) {
        let watcher = state.withLock { state in
            let watcher = state.runWatchers.removeValue(forKey: id)
            if watcher == nil {
                state.endedRunWaits.insert(id)
            }
            return watcher
        }
        watcher?.resume(returning: false)
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
