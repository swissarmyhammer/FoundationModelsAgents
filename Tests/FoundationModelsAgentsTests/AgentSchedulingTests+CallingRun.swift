@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

extension AgentSchedulingTests {
    /// Pins the rule that the run limit does not count the run that calls
    /// `start agent` (plan.md §9.3, the limit).
    ///
    /// The parent is a host-started lead run on the `standard` slot. It calls
    /// `start agent` in its task turn, then waits on a gate in that same turn.
    /// Thus the parent is working when it starts its child, and it is still
    /// working when a different caller calls `start agent`. The child is
    /// code-reviewer on the `flash` slot, and it waits on its own gate.
    @Suite("Agent scheduling: the calling run")
    struct CallingRun {
        /// The run limit of the test.
        private static let limit = 1

        /// The agent of the parent run. It can start code-reviewer.
        private static let lead = NestedRunTests.lead

        /// The agent of the child run, on the `flash` slot.
        private static let reviewer = AgentRunTests.reviewer

        /// The agent that the different caller tries to start.
        private static let testWriter = AgentRunTests.testWriter

        /// The prompt of the parent run. It is also the key of its play.
        private static let parentKey = "calling-run-parent-key: divide the task"

        /// The prompt of the child run. It is also the key of its play.
        private static let childKey = "calling-run-child-key: review the parser"

        /// The prompt of the start that the different caller tries.
        private static let otherKey = "calling-run-other-key: test the parser"

        /// The answer of the task turn of the parent run.
        private static let parentText = "I started the agent."

        /// The final text of the child run.
        private static let childText = "The parser is correct."

        /// The corrective of `start agent` when two runs are working.
        private static let limitText = """
            2 agents are working now, and that is the limit. \
            Do this part of the task yourself, or start the agent when one of them finishes.
            """

        /// The scripted `start agent` call of the parent run.
        private static let startStep = ScriptedAgentStep.toolCall(
            name: ToolVocabulary.agentsToolName,
            argumentsJSON: #"{"op": "start agent", "name": "\#(reviewer)", "prompt": "\#(childKey)"}"#)

        /// Makes the script of the test.
        ///
        /// The parent starts the child, waits on `parentGate`, and answers.
        /// Then it answers the delivery turn and the final-answer turn with
        /// the prompts that it read. The child waits on `childGate`, then
        /// answers.
        ///
        /// - Parameters:
        ///   - parentGate: The gate that holds the task turn of the parent.
        ///   - childGate: The gate that holds the turn of the child.
        /// - Returns: The script.
        private static func script(parentGate: ScriptedGate, childGate: ScriptedGate) -> ScriptedAgentScript {
            ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: parentKey,
                    steps: [
                        startStep, .wait(parentGate), .finalText(parentText),
                        .finalTextOfLaterPrompts, .finalTextOfLaterPrompts
                    ]),
                ScriptedAgentPlay(key: childKey, steps: [.wait(childGate), .finalText(childText)])
            ])
        }

        @Test(
            "at a limit of one, a working parent starts one child, and a start by another caller is the corrective",
            .timeLimit(.minutes(1)))
        func limitDoesNotCountCallingRun() async throws {
            let parentGate = ScriptedGate()
            let childGate = ScriptedGate()
            let harness = try await AgentsToolHarness.make(
                script: Self.script(parentGate: parentGate, childGate: childGate), maxConcurrentAgents: Self.limit)
            defer { try? harness.delete() }

            let parent = try await harness.runner.start(Self.lead, prompt: Self.parentKey)
            await parentGate.waitForArrival()
            await childGate.waitForArrival()
            let child = try #require(await harness.runner.runs(caller: parent.id).first)
            let refused = try await harness.call(
                "start agent", ["name": Self.testWriter, "prompt": Self.otherKey])
            let workingRuns = await harness.runner.runs
            parentGate.open()
            childGate.open()
            let result = try await parent.result()

            #expect(refused == Self.limitText)
            #expect(workingRuns.map(\.id) == [parent.id, child.id])
            #expect(try await child.result() == Self.childText)
            #expect(result.contains(Self.childText))
        }
    }
}
