import FoundationModelsRouter

/// What ``AgentRun/deliver(_:from:)`` did with a message from the caller of a
/// run.
public enum AgentRunMessageOutcome: Sendable, Equatable {
    /// The run accepted the message. The session of the run answers it
    /// before the run ends. The value is the id of the mail of the message in
    /// the session of the run: the id of the mail that was sent, or the id
    /// that a held message gets when the run sends it. The run makes the mail
    /// when it accepts the message, and a held mail stays the same mail.
    case delivered(MailID)

    /// The run ended, or it started to end, before the message arrived. The
    /// run did not accept the message. The state is the final state of the
    /// run.
    case ended(AgentRunState)

    /// `true` when the run accepted the message.
    public var isDelivered: Bool {
        mailID != nil
    }

    /// The id of the mail of the message in the session of the run, or `nil`
    /// when the run did not accept the message. A caller that tested the outcome with
    /// `== .delivered` uses ``isDelivered`` now: the case carries the id, a source break by design.
    public var mailID: MailID? {
        if case .delivered(let id) = self { id } else { nil }
    }
}
