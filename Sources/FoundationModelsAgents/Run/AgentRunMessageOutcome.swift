/// What ``AgentRun/deliver(_:)`` did with a message from the caller of a
/// run.
enum AgentRunMessageOutcome: Sendable, Equatable {
    /// The run accepted the message. The session of the run answers it
    /// before the run ends.
    case delivered

    /// The run ended, or it started to end, before the message arrived. The
    /// run did not accept the message. The state is the final state of the
    /// run.
    case ended(AgentRunState)
}
