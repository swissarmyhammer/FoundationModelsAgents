import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

extension LiveSuites {
    /// The full circle of one delegation on real models (plan.md §9, §15).
    ///
    /// A root session on the `standard` slot has the `agents` tool. Its model
    /// calls `start agent`. The sub-agent runs on the `standard` slot after
    /// the turn of the root ends. It calls ``LiveWordTool``, and answers with
    /// the secret word. The larger model follows the tool instruction better
    /// than the `flash` model. Its final message is in the root transcript,
    /// and the next turn of the root reads it.
    /// Then `check agent`, called as the root session, gives the same text.
    ///
    /// `check agent` answers only for a run of the caller. The test keeps the
    /// `ToolContext` of the `start agent` call of the root with
    /// ``LiveAgentsToolProbe``, and calls `check agent` in that context. Thus
    /// the check does not depend on a choice of the model.
    ///
    /// The test asserts on recorded facts: the calls of the tool, the
    /// `agentSpawn` of the sub-agent, and the posts in the root transcript.
    @Suite("Full circle", .serialized, .timeLimit(LiveProfile.timeLimit))
    struct FullCircleTests {
        /// The sub-agent.
        private static let finder = "word-finder"

        /// The task that the root gives to the sub-agent.
        private static let task = "Find the secret word."

        @Test("start agent, a tool of the sub-agent, the final message, the next turn, and check agent")
        func delegationGoesFullCircle() async throws {
            let wordTool = LiveWordTool()
            let agents = [
                LiveAgentFile.path(of: Self.finder): LiveAgentFile.text(
                    id: Self.finder,
                    description: "Finds the secret word with a tool.",
                    fields: ["model: standard", "tools: \(LiveWordTool.toolName)"],
                    body: LiveAgentFile.toolWordBody(toolName: LiveWordTool.toolName))
            ]

            try await LiveHarness.withHarness(agents: agents, tools: [wordTool]) { harness in
                let agentsTool = try await harness.makeAgentsTool()
                let probe = LiveAgentsToolProbe(wrapping: agentsTool)
                let root = harness.makeRootSession(tools: [probe])
                _ = try await root.respond(
                    to: try LiveHarness.agentsCallText([
                        "op": LiveHarness.startOperation, "name": Self.finder, "prompt": Self.task
                    ]))
                let finder = try LiveHarness.run(of: Self.finder, in: await harness.runner.runs(caller: root.id))
                let text = try await finder.result()
                _ = try await root.dispatchNextPrompt()
                await root.close()
                let spawn = try #require(try LiveRecording.session(of: finder).agentSpawn)
                let startContext = try #require(
                    probe.callContexts.first { $0.completionToken == spawn.parentToolCallId })
                let check = try await ToolContext.$current.withValue(startContext) {
                    try await harness.call(agentsTool, LiveHarness.checkOperation, ["id": finder.id.description])
                }

                let posted = try LiveRecording.operationEvents(of: .toolOutput, in: root.recordingDirectory)
                    .filter { $0.correlationID == spawn.parentToolCallId }
                let read = try LiveRecording.operationEvents(of: .prompt, in: root.recordingDirectory)
                    .filter { $0.correlationID == spawn.parentToolCallId }

                #expect(wordTool.callCount > 0)
                #expect(text.localizedCaseInsensitiveContains(LiveWordTool.word), "The final text was: \(text)")
                #expect(startContext.sessionID == root.id)
                #expect(spawn.parentSessionId == root.id)
                #expect(posted.map(\.kind) == [.completed])
                #expect(posted.map(\.detail) == [text])
                #expect(read.map(\.detail) == [text])
                #expect(check.contains(finder.id.description) && check.hasSuffix(text), "The check gave: \(check)")
            }
        }
    }
}
