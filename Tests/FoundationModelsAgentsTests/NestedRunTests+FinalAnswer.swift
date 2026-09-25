@testable import FoundationModelsAgents
import Testing

extension NestedRunTests {
    /// Pins the final-answer turn (plan.md §8 step 8): when no child is open
    /// and no post is unread after a delivery turn, the run sends
    /// ``AgentRun/finalAnswerPrompt``, and the text of that turn is the
    /// result. A final-answer turn that starts a child makes the run wait
    /// for that child and send the prompt again. A run that starts no child
    /// gets no final-answer prompt.
    ///
    /// The `lead` run is on the `standard` slot. Its child code-reviewer is
    /// on the `flash` slot, and its child test-writer is on the `standard`
    /// slot.
    @Suite("Final-answer turn")
    struct FinalAnswer {
        /// The answer of the first final-answer turn, after the lead started
        /// one more child in it.
        private static let restartedText = "I started one more agent."

        @Test(
            "a final-answer turn that starts a child waits for it, and one more final-answer turn ends the run",
            .timeLimit(.minutes(1)))
        func finalAnswerTurnThatStartsChildWaitsForIt() async throws {
            let harness = try await AgentRunHarness.make(
                script: ScriptedAgentScript([
                    ScriptedAgentPlay(
                        key: NestedRunTests.leadKey,
                        steps: [
                            NestedRunTests.startStep(NestedRunTests.reviewer, prompt: NestedRunTests.reviewerKey),
                            .finalText(NestedRunTests.startedText),
                            .finalTextOfLastPrompt,
                            NestedRunTests.startStep(NestedRunTests.testWriter, prompt: NestedRunTests.testWriterKey),
                            .finalText(Self.restartedText),
                            .finalTextOfLastPrompt,
                            NestedRunTests.finalAnswerStep
                        ]),
                    ScriptedAgentPlay(
                        key: NestedRunTests.reviewerKey, steps: [.finalText(NestedRunTests.reviewerText)]),
                    ScriptedAgentPlay(
                        key: NestedRunTests.testWriterKey, steps: [.finalText(NestedRunTests.testWriterText)])
                ]))
            defer { try? harness.delete() }
            let runner = harness.makeRunner()

            let lead = try await runner.start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
            let result = try await lead.result()
            let children = await runner.runs(caller: lead.id)
            let prompts = harness.script.prompts
            let finalAnswerPositions = prompts.indices.filter { prompts[$0] == AgentRun.finalAnswerPrompt }
            let firstFinalAnswer = try #require(finalAnswerPositions.first)
            let lastFinalAnswer = try #require(finalAnswerPositions.last)
            let testWriterPost = try #require(prompts.firstIndex { $0.contains(NestedRunTests.testWriterText) })

            #expect(result.contains(NestedRunTests.reviewerText))
            #expect(result.contains(NestedRunTests.testWriterText))
            #expect(children.map(\.agent.id).sorted() == [NestedRunTests.reviewer, NestedRunTests.testWriter])
            #expect(finalAnswerPositions.count == 2)
            #expect(firstFinalAnswer < testWriterPost)
            #expect(testWriterPost < lastFinalAnswer)
            #expect(lastFinalAnswer == prompts.indices.last)
        }

        @Test("a run that starts no child gets no final-answer prompt", .timeLimit(.minutes(1)))
        func runWithNoChildGetsNoFinalAnswerPrompt() async throws {
            let harness = try await AgentRunHarness.make(
                script: ScriptedAgentScript([
                    ScriptedAgentPlay(key: NestedRunTests.leadKey, steps: [.finalText(NestedRunTests.startedText)])
                ]))
            defer { try? harness.delete() }

            let lead = try await harness.makeRunner().start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
            let result = try await lead.result()
            let prompts = harness.script.prompts

            #expect(result == NestedRunTests.startedText)
            #expect(prompts.count == 1)
            #expect(!prompts.contains(AgentRun.finalAnswerPrompt))
        }
    }
}
