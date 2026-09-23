@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins the `lastEvent` phrases of a run in operation (plan.md §9.1,
/// `check agent`: "is running: `lastEvent`").
@Suite("Agent run activity")
struct AgentRunActivityTests {
    /// The id of the tool call of each event.
    private static let callID = "activity-call"

    /// A text fragment of each text event.
    private static let fragment = "The work is correct."

    /// Makes a tool status event.
    ///
    /// - Parameter status: The status of the tool call.
    /// - Returns: The event.
    private static func statusEvent(_ status: ToolCallStatus) -> SessionEvent {
        .toolStatus(id: callID, status: status, summary: nil, output: nil)
    }

    @Test("each event of work gives a short phrase, and a running tool status gives none")
    func eventsGivePhrases() {
        #expect(AgentRunActivity.phrase(for: .textDelta(Self.fragment)) == "the model writes its answer")
        #expect(AgentRunActivity.phrase(for: .textReset) == "the model writes its answer")
        #expect(AgentRunActivity.phrase(for: .reasoningDelta(Self.fragment)) == "the model reasons")
        #expect(
            AgentRunActivity.phrase(for: .toolCall(id: Self.callID, name: "Read", argumentsJSON: "{}"))
                == "it called the tool Read")
        #expect(AgentRunActivity.phrase(for: Self.statusEvent(.completed)) == "a tool call ended")
        #expect(AgentRunActivity.phrase(for: Self.statusEvent(.failed)) == "a tool call failed")
        #expect(AgentRunActivity.phrase(for: Self.statusEvent(.running)) == nil)
        #expect(AgentRunActivity.started == "the turn started")
    }
}
