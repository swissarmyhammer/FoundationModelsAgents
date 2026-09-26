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
/// The Router can call the canceler before the body of the call started the
/// run. The record then keeps the cancel, and the run is cancelled at once
/// when the body adds it.
///
/// A class, because each copy of the tool and its context share one record.
/// A `Mutex` guards the state, thus the `Sendable` conformance is
/// compiler-checked.
final class StartedRuns: Sendable {
    /// The state that the lock guards.
    private struct State {
        /// The runs, by the completion token of the call that started each.
        var runs: [String: AgentRun] = [:]

        /// The tokens of the calls that the Router cancelled before their
        /// body added a run.
        var cancelled: Set<String> = []
    }

    /// The runs and the early cancels.
    private let state = Mutex(State())

    /// Makes an empty record.
    init() {}

    /// Adds the run that the call `token` started. When the Router cancelled
    /// that call already, the run is cancelled at once.
    ///
    /// - Parameters:
    ///   - run: The run.
    ///   - token: The completion token of the call.
    func add(_ run: AgentRun, forCall token: String) {
        let isCancelled = state.withLock { state in
            state.runs[token] = run
            return state.cancelled.remove(token) != nil
        }
        if isCancelled {
            run.cancel()
        }
    }

    /// Gives the run that the call `token` started.
    ///
    /// - Parameter token: The completion token of the call.
    /// - Returns: The run, or `nil` when no call with that token started one.
    func run(forCall token: String) -> AgentRun? {
        state.withLock { $0.runs[token] }
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
}
