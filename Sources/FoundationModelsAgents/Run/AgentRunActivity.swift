import FoundationModelsRouter

/// The short phrases that tell what a run in operation did last
/// (plan.md §9.1, `check agent`: "is running: `lastEvent`").
///
/// The run keeps the phrase of the last event of its turn that tells a kind
/// of work. An event that tells no kind of work, for example a token count,
/// keeps the phrase that came before it.
enum AgentRunActivity {
    /// The phrase of a run before its turn gives an event of work.
    static let started = "the turn started"

    /// The phrase of text or of a text reset.
    static let writing = "the model writes its answer"

    /// The phrase of a reasoning fragment.
    static let reasoning = "the model reasons"

    /// The phrase of a tool call that returned.
    static let toolEnded = "a tool call ended"

    /// The phrase of a tool call that failed.
    static let toolFailed = "a tool call failed"

    /// Gives the phrase of one event of the turn.
    ///
    /// `SessionEvent` has no library evolution, and new cases can come. Thus
    /// the phrase uses `if case` tests, and each event that it does not name
    /// gives `nil`.
    ///
    /// - Parameter event: An event of the turn.
    /// - Returns: The phrase, or `nil` when the event tells no kind of work.
    static func phrase(for event: SessionEvent) -> String? {
        if case .toolCall(_, let name, _) = event {
            return "it called the tool \(name)"
        }
        if case .toolStatus(_, let status, _, _) = event {
            return phrase(for: status)
        }
        if case .textDelta = event {
            return writing
        }
        if case .textReset = event {
            return writing
        }
        if case .reasoningDelta = event {
            return reasoning
        }
        if case .turnStarted = event {
            return started
        }
        return nil
    }

    /// Gives the phrase of the status of a tool call.
    ///
    /// - Parameter status: The status of the tool call.
    /// - Returns: The phrase of an ended or a failed call, or `nil` for a
    ///   call in operation: the tool-call event already told it.
    private static func phrase(for status: ToolCallStatus) -> String? {
        switch status {
        case .running:
            nil
        case .completed:
            toolEnded
        case .failed:
            toolFailed
        }
    }
}
