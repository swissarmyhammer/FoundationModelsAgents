@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

extension AgentRunTests {
    /// Pins the lineage of a run (plan.md §8.2, §16): a run started inside a
    /// tool call of a Router session records `agentSpawn`, and a host-driven
    /// run records none.
    @Suite("Agent run lineage")
    struct Lineage {
        /// The key of the play of the parent session.
        private static let parentKey = "parent-play-key"

        /// The prompt of the parent session.
        private static let parentPrompt = "Start the reviewer."

        /// The final text of the parent session.
        private static let parentFinalText = "The parent started a reviewer."

        /// The arguments of the scripted call of the probe tool.
        private static let probeArguments = #"{"text":"start"}"#

        /// The text of the operation event that the test posts.
        private static let postedDetail = "The reviewer finished."

        /// Makes the script of the lineage test: the parent calls the probe
        /// tool, and the run answers with the final text.
        ///
        /// - Returns: A new script.
        private static func makeScript() -> ScriptedAgentScript {
            ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: parentKey,
                    steps: [
                        .toolCall(name: AgentStartProbe.toolName, argumentsJSON: probeArguments),
                        .finalText(parentFinalText)
                    ]),
                ScriptedAgentPlay(key: AgentRunTests.prompt, steps: [.finalText(AgentRunTests.finalText)])
            ])
        }

        /// The `ToolContext.completionToken` of the call joins to the call:
        /// the Router journals a post through that context into the parent
        /// transcript with the token and the tool name.
        @Test("a run started in a tool call records agentSpawn that joins to the call in the Router transcript")
        func toolCallRunRecordsAgentSpawn() async throws {
            let harness = try await AgentRunHarness.make(script: Self.makeScript())
            defer { try? harness.delete() }
            let probe = AgentStartProbe { context in
                try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt, context: context)
            }
            let parent = harness.profile.standard.makeSession(instructions: Self.parentKey, tools: [probe])

            #expect(try await parent.respond(to: Self.parentPrompt) == Self.parentFinalText)
            let started = try #require(probe.started)
            let context = try #require(started.context)
            #expect(try await started.run.result() == AgentRunTests.finalText)
            let spawn = try #require(try AgentRunTests.sidecar(of: started.run).agentSpawn)
            await context.post(
                OperationEvent(
                    tool: context.tool, op: context.op, correlationID: context.completionToken,
                    kind: .completed, detail: Self.postedDetail))
            await parent.close()
            let journaled = try RecordedTranscript.operationEvents(in: parent.recordingDirectory)
                .filter { $0.correlationID == spawn.parentToolCallId }

            #expect(
                spawn
                    == SessionSidecar.AgentSpawn(
                        parentSessionId: parent.id, parentToolCallId: context.completionToken))
            #expect(started.run.caller == parent.id)
            #expect(journaled.map(\.tool) == [AgentStartProbe.toolName])
            #expect(journaled.map(\.detail) == [Self.postedDetail])
        }

        @Test("a host-driven run records no agentSpawn")
        func hostDrivenRunRecordsNoAgentSpawn() async throws {
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]))
            defer { try? harness.delete() }

            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            _ = try await run.result()

            #expect(try AgentRunTests.sidecar(of: run).agentSpawn == nil)
            #expect(run.caller == nil)
        }
    }
}
