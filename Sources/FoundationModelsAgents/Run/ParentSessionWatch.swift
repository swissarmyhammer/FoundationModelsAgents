import FoundationModelsRouter
import Synchronization

/// What the `start agent` calls of a run and the run itself wait for in the
/// session of the run (plan.md §9.2).
///
/// The run gives each event of its session-event subscription to
/// ``observe(_:)``. Two waits read the result:
///
/// - The end of the submission of a call. The background body of
///   `start agent` gives its final message only after the submission that
///   made the call ended. The Router waits `inlineSettleGrace` in that
///   submission before it answers the call, and a run that settles in that
///   wait gives its result in the tool output, not as mail. Thus this wait
///   keeps each final message as mail: the call returns at once with the
///   pending envelope, and the final message comes later as a message.
/// - The settlement of a call. Before the run closes its session, it waits
///   until the Router recorded the final message of each run that it
///   started. Thus the recording of the session holds each final message.
///
/// The key of each wait is the completion token of the call. The Router
/// sends the open ``SessionEvent/toolInvocation(_:)`` record of a call before
/// the body of the call starts, and the ``SessionEvent/submissionEnded(_:)``
/// of that submission after the call answered. The watch reads the events in
/// the order that the Router sends them, thus a submission end after the open
/// record of a call is the end of the submission of that call.
///
/// A class, because the run and the `agents` tool of the run share one watch.
/// A `Mutex` guards the state, thus the `Sendable` conformance is
/// compiler-checked.
final class ParentSessionWatch: Sendable {
    /// The state that the lock guards.
    private struct State {
        /// The tokens of the calls whose open record came in the submission
        /// in operation.
        var openInSubmission: Set<String> = []

        /// The tokens of the calls whose submission ended.
        var submissionEnded: Set<String> = []

        /// The tokens of the runs whose terminal the Router recorded.
        var settled: Set<String> = []

        /// The waits for the end of the submission of a call, by token.
        var endWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

        /// The waits for the settlement of a call, by token.
        var settlementWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

        /// `true` after the session-event subscription finished. Each wait
        /// then returns at once.
        var isFinished = false
    }

    /// The state of the watch.
    private let state = Mutex(State())

    /// Makes an empty watch.
    init() {}

    /// Applies one event of the session-event subscription of the run, and
    /// resumes each wait that the event completes.
    ///
    /// - Parameter event: The event.
    func observe(_ event: SessionEvent) {
        if case .toolInvocation(let record) = event, record.closedAt == nil {
            state.withLock { _ = $0.openInSubmission.insert(record.correlationID) }
        }
        if case .submissionEnded = event {
            resume(takingEndWaiters())
        }
        if case .runSettled(let terminal) = event {
            resume(takingSettlementWaiters(of: terminal.correlationID))
        }
    }

    /// Ends the watch when the session-event subscription finished. Each
    /// wait returns, now and later.
    func finish() {
        let waiters = state.withLock { state in
            state.isFinished = true
            let waiters = Array(state.endWaiters.values.joined()) + Array(state.settlementWaiters.values.joined())
            state.endWaiters = [:]
            state.settlementWaiters = [:]
            return waiters
        }
        resume(waiters)
    }

    /// Waits until the submission that made the call `token` ended.
    ///
    /// - Parameter token: The completion token of the call.
    func waitForEndOfSubmission(ofCall token: String) async {
        await withCheckedContinuation { continuation in
            let isDone = state.withLock { state in
                guard !state.isFinished, state.submissionEnded.remove(token) == nil else {
                    return true
                }
                state.endWaiters[token, default: []].append(continuation)
                return false
            }
            if isDone {
                continuation.resume()
            }
        }
    }

    /// Waits until the Router recorded the terminal of each call of `tokens`.
    ///
    /// - Parameter tokens: The completion tokens of the calls.
    func waitForSettlement(ofCalls tokens: [String]) async {
        for token in tokens {
            await waitForSettlement(ofCall: token)
        }
    }

    /// Waits until the Router recorded the terminal of the call `token`.
    ///
    /// - Parameter token: The completion token of the call.
    private func waitForSettlement(ofCall token: String) async {
        await withCheckedContinuation { continuation in
            let isDone = state.withLock { state in
                guard !state.isFinished, !state.settled.contains(token) else {
                    return true
                }
                state.settlementWaiters[token, default: []].append(continuation)
                return false
            }
            if isDone {
                continuation.resume()
            }
        }
    }

    /// Moves each call of the submission in operation to the ended calls,
    /// and takes the waits of those calls.
    ///
    /// A call with a wait leaves no token behind. A call with no wait yet
    /// keeps its token in the ended calls until its wait comes.
    ///
    /// - Returns: The waits to resume.
    private func takingEndWaiters() -> [CheckedContinuation<Void, Never>] {
        state.withLock { state in
            let ended = state.openInSubmission
            state.openInSubmission = []
            let waiting = ended.filter { state.endWaiters[$0] != nil }
            state.submissionEnded.formUnion(ended.subtracting(waiting))
            return waiting.flatMap { state.endWaiters.removeValue(forKey: $0) ?? [] }
        }
    }

    /// Records the terminal of the call `token`, and takes the waits of that
    /// call.
    ///
    /// - Parameter token: The completion token of the call.
    /// - Returns: The waits to resume.
    private func takingSettlementWaiters(of token: String) -> [CheckedContinuation<Void, Never>] {
        state.withLock { state in
            state.settled.insert(token)
            return state.settlementWaiters.removeValue(forKey: token) ?? []
        }
    }

    /// Resumes each wait of `waiters`.
    ///
    /// - Parameter waiters: The waits.
    private func resume(_ waiters: [CheckedContinuation<Void, Never>]) {
        for waiter in waiters {
            waiter.resume()
        }
    }
}
