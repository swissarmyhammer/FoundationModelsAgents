import Synchronization

/// The runs that the `start agent` calls of one `agents` tool started, by
/// the completion token of each call (plan.md §9.1, §9.2).
///
/// The Router gives the model the pending envelope of a `start agent` call.
/// The envelope holds the completion token of the call, not the id of the
/// run. Thus `check agent` and `cancel agent` find a run by that token too.
/// The Router cancels a background call through the canceler of the tool,
/// and the canceler finds the run by the same token.
///
/// The Router gives the envelope before the body of the call starts the
/// run. Thus the record knows each call from the time that the Router asks
/// for its canceler (``open(call:)``) to the time that its body adds a run
/// (``add(_:forCall:)``) or ends with no run (``close(call:)``). While a call
/// is open, ``waitForStart(ofCall:)`` and ``waitForStarts()`` wait for it.
/// Thus a `check agent` or a `cancel agent` in the next pass of the model
/// finds the run of the call.
///
/// The Router can call the canceler before the body of the call started the
/// run. The record then keeps the cancel, and the run is cancelled at once
/// when the body adds it.
///
/// A class, because each copy of the tool and its context share one record.
/// A `Mutex` guards the state, thus the `Sendable` conformance is
/// compiler-checked.
final class StartedRuns: Sendable {
    /// One task that waits until an open call adds its run or ends.
    private typealias Waiter = CheckedContinuation<Void, Never>

    /// The state that the lock guards.
    private struct State {
        /// The runs, by the completion token of the call that started each.
        var runs: [String: AgentRun] = [:]

        /// The tokens of the calls that the Router cancelled before their
        /// body added a run.
        var cancelled: Set<String> = []

        /// The calls whose body did not add a run and did not end yet, by
        /// token, with the tasks that wait for each.
        var openCalls: [String: [Waiter]] = [:]

        /// Ends the open call `token`.
        ///
        /// - Parameter token: The completion token of the call.
        /// - Returns: The tasks that waited for the call. The caller resumes
        ///   them outside the lock.
        mutating func endOpenCall(_ token: String) -> [Waiter] {
            openCalls.removeValue(forKey: token) ?? []
        }
    }

    /// The runs, the early cancels, and the open calls.
    private let state = Mutex(State())

    /// Makes an empty record.
    init() {}

    /// Records the call `token` before its body runs. From now on, until the
    /// body adds a run or ends, ``waitForStart(ofCall:)`` and
    /// ``waitForStarts()`` wait for the call.
    ///
    /// - Parameter token: The completion token of the call.
    func open(call token: String) {
        state.withLock { state in
            guard state.runs[token] == nil, state.openCalls[token] == nil else {
                return
            }
            state.openCalls[token] = []
        }
    }

    /// Adds the run that the call `token` started, and ends the open call.
    /// When the Router cancelled that call already, the run is cancelled at
    /// once.
    ///
    /// - Parameters:
    ///   - run: The run.
    ///   - token: The completion token of the call.
    func add(_ run: AgentRun, forCall token: String) {
        let (isCancelled, waiters) = state.withLock { state in
            state.runs[token] = run
            return (state.cancelled.remove(token) != nil, state.endOpenCall(token))
        }
        if isCancelled {
            run.cancel()
        }
        Self.resume(waiters)
    }

    /// Ends the call `token` when its body ends. A call whose body added no
    /// run then stays unknown, and the record drops the early cancel of that
    /// call. A call that added a run keeps its run.
    ///
    /// - Parameter token: The completion token of the call.
    func close(call token: String) {
        let waiters = state.withLock { state in
            if state.runs[token] == nil {
                state.cancelled.remove(token)
            }
            return state.endOpenCall(token)
        }
        Self.resume(waiters)
    }

    /// Gives the run that the call `token` started.
    ///
    /// - Parameter token: The completion token of the call.
    /// - Returns: The run, or `nil` when no call with that token started one.
    func run(forCall token: String) -> AgentRun? {
        state.withLock { $0.runs[token] }
    }

    /// Waits until the call `token` adds its run or ends. Returns at once
    /// when the call is not open.
    ///
    /// - Parameter token: The completion token of the call, or any other id.
    func waitForStart(ofCall token: String) async {
        await withCheckedContinuation { (waiter: Waiter) in
            let isOpen = state.withLock { state in
                state.openCalls[token]?.append(waiter) != nil
            }
            if !isOpen {
                waiter.resume()
            }
        }
    }

    /// Waits until each call that is open now adds its run or ends.
    func waitForStarts() async {
        let tokens = state.withLock { Array($0.openCalls.keys) }
        for token in tokens {
            await waitForStart(ofCall: token)
        }
    }

    /// Cancels the run that the call `token` started. When the call has no
    /// run yet, the record keeps the cancel for it.
    ///
    /// - Parameter token: The completion token of the call.
    func cancelRun(ofCall token: String) {
        let run = state.withLock { state in
            guard let run = state.runs[token] else {
                state.cancelled.insert(token)
                return AgentRun?.none
            }
            return run
        }
        run?.cancel()
    }

    /// Resumes each task that waited for an open call.
    ///
    /// - Parameter waiters: The tasks.
    private static func resume(_ waiters: [Waiter]) {
        for waiter in waiters {
            waiter.resume()
        }
    }
}
