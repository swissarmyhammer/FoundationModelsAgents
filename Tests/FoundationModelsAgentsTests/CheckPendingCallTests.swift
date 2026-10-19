import FoundationModels
import FoundationModelsRouter
import Synchronization
import Testing

@testable import FoundationModelsAgents

/// Pins the answer of `check agent` for the completion token of a pending
/// call of another tool.
///
/// In a SWE-bench run of 2026-10-18, a model called `check agent` with the
/// completion token of one of its own code snippets. "No run has the id …"
/// was correct, but it did not tell the model that the token is a call whose
/// result comes as a message.
@Suite("check agent with the token of a pending call")
struct CheckPendingCallTests {
    /// The instructions of the root session. They are also the key of its
    /// play.
    private static let rootKey = "check-pending-call-root-key"

    /// The prompt and the final answer of the root session.
    private static let rootText = "Check the call."

    @Test("check agent with the token of a pending call of another tool says that its result comes as a message")
    func checkWithThePendingTokenOfAnotherTool() async throws {
        let probe = PendingCallProbe()
        let harness = try await AgentsToolHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: Self.rootKey,
                    steps: [
                        .toolCall(name: PendingCallProbe.toolName, argumentsJSON: #"{"text":"check"}"#),
                        .finalText(Self.rootText)
                    ])
            ]))
        defer { try? harness.delete() }
        probe.agentsTool.withLock { $0 = harness.tool }
        let root = AgentRunHarness.makeRootSession(
            on: harness.runHarness.profile.standard, instructions: Self.rootKey, tools: [probe])

        _ = try await root.respond(to: Self.rootText)
        await root.close()
        let checked = try #require(probe.checked.withLock { $0 })

        #expect(
            checked.answer
                == AgentsToolText.pendingCallOfAnotherTool(checked.token, tool: PendingCallProbe.toolName))
    }

    @Test("check agent with a token that no call has keeps the no-run answer")
    func checkWithAnUnknownTokenKeepsTheNoRunAnswer() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await harness.call("check agent", ["id": "no-such-call"])

        #expect(answer == "No run has the id no-such-call. You have no runs.")
    }
}

/// A background tool whose call asks the `agents` tool to check its own
/// completion token, and keeps the answer.
///
/// While the body runs, the call is a pending background run of the session,
/// thus `ToolContext.backgroundRuns()` holds it.
private final class PendingCallProbe: Tool, BackgroundTool {
    /// The arguments of the tool: one text.
    @Generable
    struct Arguments {
        /// A text that the tool ignores.
        let text: String
    }

    /// The token of the call, and the answer of `check agent` for it.
    struct Checked: Sendable {
        /// The completion token of the call.
        let token: String

        /// The answer of `check agent`.
        let answer: String
    }

    /// The name that a scripted step calls the tool by.
    static let toolName = "pending-call-probe"

    /// The name of the tool.
    let name = PendingCallProbe.toolName

    /// The description of the tool.
    let description = "Checks its own completion token with the agents tool."

    /// Each call is a background run.
    let mount: ToolMount? = ToolMount(mode: .background)

    /// The `agents` tool that the call asks. The test sets it before the
    /// session starts.
    let agentsTool = Mutex<AgentsTool?>(nil)

    /// The token and the answer of the last call, or `nil` before a call.
    let checked = Mutex<Checked?>(nil)

    /// Calls `check agent` with the completion token of this call.
    ///
    /// - Parameter arguments: The arguments, which the tool ignores.
    /// - Returns: The answer of `check agent`.
    /// - Throws: The error of the `agents` tool.
    func call(arguments: Arguments) async throws -> String {
        guard let context = ToolContext.current, let tool = agentsTool.withLock({ $0 }) else {
            return "The probe has no context or no agents tool."
        }
        let token = context.completionToken
        let answer = try await tool.call(
            arguments: GeneratedContent(properties: ["op": "check agent", "id": token]))
        checked.withLock { $0 = Checked(token: token, answer: answer) }
        return answer
    }
}
