/// The hold of the mail of a run in operation (``AgentRun/pause``).
///
/// The Router holds the final messages of the runs that a run started when
/// too many answers in a row came from mail alone. The run then waits for
/// each run that it started, and ends with the held results. A message from
/// its caller ends the hold, and the run goes on.
public struct AgentRunPause: Sendable, Equatable {
    /// The description of the hold that the Router gives.
    public let description: String

    /// The count of runs that this run started and that did not end. The run
    /// ends when this count is zero, if no message from its caller ends the
    /// hold first.
    public let openChildren: Int
}
