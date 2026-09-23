/// The state of one agent run (plan.md §8.1, §12).
///
/// A run starts in ``running``. It then goes to one of the three terminal
/// states one time, and stays there.
public enum AgentRunState: Sendable, Equatable {
    /// The turn of the run is in operation.
    case running

    /// The run finished. The text is the text of the last turn: the result
    /// of the run.
    case finished(String)

    /// The run failed for the reason.
    case failed(AgentRunFailure)

    /// The run was cancelled before its turn finished.
    case cancelled
}
