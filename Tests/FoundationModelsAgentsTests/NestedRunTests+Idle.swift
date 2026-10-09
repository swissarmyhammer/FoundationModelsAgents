@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

extension NestedRunTests {
    /// Pins the end of a run with children: `start agent` is a background
    /// call that answers at once with the pending envelope, the final message
    /// of a child comes to the parent as mail, the pump of the Router starts
    /// the answer to that mail, and the run ends only when its session is
    /// idle. The reply of the last answer is the result.
    @Suite("Runs end when the session is idle")
    struct Idle {
        /// The mark of a pending envelope of the Router in a tool output.
        private static let pendingMark = #""pending":true"#

        /// The answer of the answer to mail that starts one more child.
        private static let restartedText = "I started one more agent."

        /// The count of prompts of a parent that starts one child: its task
        /// prompt, the prompt of the child, and the mail of the child.
        private static let oneChildPromptCount = 3

        @Test(
            "a parent and a child on one model: the submission of the parent ends after start agent; mail comes next",
            .timeLimit(.minutes(1)))
        func parentAndChildOnOneModel() async throws {
            let harness = try await AgentRunHarness.make(
                script: ScriptedAgentScript([
                    ScriptedAgentPlay(
                        key: NestedRunTests.leadKey,
                        steps: [
                            NestedRunTests.startStep(NestedRunTests.testWriter, prompt: NestedRunTests.testWriterKey),
                            .finalText(NestedRunTests.startedText),
                            .finalTextOfLastPrompt
                        ]),
                    ScriptedAgentPlay(
                        key: NestedRunTests.testWriterKey, steps: [.finalText(NestedRunTests.testWriterText)])
                ]))
            defer { try? harness.delete() }
            let runner = harness.makeRunner()

            let lead = try await runner.start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
            let result = try await lead.result()
            let child = try await NestedRunTests.onlyRun(of: runner, caller: lead.id)
            let prompts = harness.script.prompts

            #expect(lead.slot == .standard)
            #expect(child.slot == .standard)
            #expect(harness.script.toolOutputs.first?.contains(Self.pendingMark) == true)
            #expect(prompts.count == Self.oneChildPromptCount)
            #expect(prompts.first == NestedRunTests.leadKey)
            #expect(prompts.dropFirst().first?.contains(NestedRunTests.testWriterKey) == true)
            #expect(prompts.last?.contains(child.report) == true)
            #expect(result == prompts.last)
        }

        @Test(
            "a child on its own model that ends at once still comes as mail, not in the output of start agent",
            .timeLimit(.minutes(1)))
        func fastChildOnOtherModelComesAsMail() async throws {
            let harness = try await AgentRunHarness.make(
                script: ScriptedAgentScript([
                    NestedRunTests.parentPlay(
                        NestedRunTests.leadKey, children: [(NestedRunTests.reviewer, NestedRunTests.reviewerKey)]),
                    ScriptedAgentPlay(key: NestedRunTests.reviewerKey, steps: [.finalText(NestedRunTests.reviewerText)])
                ]))
            defer { try? harness.delete() }
            let runner = harness.makeRunner()

            let lead = try await runner.start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
            let result = try await lead.result()
            let child = try await NestedRunTests.onlyRun(of: runner, caller: lead.id)

            #expect(harness.profile.standard.chosen.stringValue != harness.profile.flash.chosen.stringValue)
            #expect(harness.script.toolOutputs.first?.contains(Self.pendingMark) == true)
            #expect(harness.script.toolOutputs.allSatisfy { !$0.contains(child.report) })
            #expect(result.contains(child.report))
        }

        @Test(
            "an answer to mail that starts one more child makes the run wait for it, and answer its mail too",
            .timeLimit(.minutes(1)))
        func answerToMailThatStartsChildWaitsForIt() async throws {
            let harness = try await AgentRunHarness.make(
                script: ScriptedAgentScript([
                    ScriptedAgentPlay(
                        key: NestedRunTests.leadKey,
                        steps: [
                            NestedRunTests.startStep(NestedRunTests.reviewer, prompt: NestedRunTests.reviewerKey),
                            .finalText(NestedRunTests.startedText),
                            NestedRunTests.startStep(NestedRunTests.testWriter, prompt: NestedRunTests.testWriterKey),
                            .finalText(Self.restartedText),
                            .finalTextOfLastPrompt
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
            let testWriter = try #require(children.first { $0.agent.id == NestedRunTests.testWriter })

            #expect(children.map(\.agent.id).sorted() == [NestedRunTests.reviewer, NestedRunTests.testWriter])
            #expect(result.contains(testWriter.report))
            #expect(harness.script.prompts.last == result)
        }

        @Test("a run that starts no child ends with the reply of the answer of its task prompt",
            .timeLimit(.minutes(1)))
        func runWithNoChildEndsWithTaskAnswer() async throws {
            let harness = try await AgentRunHarness.make(
                script: ScriptedAgentScript([
                    ScriptedAgentPlay(key: NestedRunTests.leadKey, steps: [.finalText(NestedRunTests.startedText)])
                ]))
            defer { try? harness.delete() }

            let lead = try await harness.makeRunner().start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
            let result = try await lead.result()

            #expect(result == NestedRunTests.startedText)
            #expect(harness.script.prompts == [NestedRunTests.leadKey])
        }
    }
}
