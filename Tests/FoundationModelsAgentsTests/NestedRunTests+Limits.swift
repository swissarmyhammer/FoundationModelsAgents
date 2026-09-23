@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

extension NestedRunTests {
    /// Pins the limits and the slots of nested runs (plan.md §7, §9.3): a
    /// run that waits for its children holds no place in the run limit, a
    /// start above `maxDepth` gives a corrective, and `model: inherit` in a
    /// child uses the slot of the calling run.
    @Suite("Nested run limits")
    struct Limits {
        /// The run limit of the sibling test.
        private static let siblingLimit = 2

        /// The depth limit of the depth test.
        private static let depthLimit = 2

        /// The agent of the temporary layer that can start each agent.
        private static let planner = "planner"

        /// The agent of the temporary layer on the `flash` slot that starts
        /// ``helper``.
        private static let flashLead = "flash-lead"

        /// The agent of the temporary layer with no `model`.
        private static let helper = "helper"

        /// The agent files of the temporary layer, by path.
        private static let agentFiles = [
            "agents/\(planner).md": """
                ---
                name: \(planner)
                description: Plans a task and gives parts of it to other agents.
                tools: Agent
                ---

                You are a planner.
                """,
            "agents/\(flashLead).md": """
                ---
                name: \(flashLead)
                description: Gives a task to the helper.
                model: flash
                tools: Agent(\(helper))
                ---

                You are a lead on the flash slot.
                """,
            "agents/\(helper).md": """
                ---
                name: \(helper)
                description: Does one part of a task.
                ---

                You are a helper.
                """
        ]

        /// The key of the play of the first sibling lead.
        private static let firstSiblingKey = "nested-first-sibling-key: divide the task"

        /// The key of the play of the second sibling lead.
        private static let secondSiblingKey = "nested-second-sibling-key: divide the task"

        /// The key of the play of the child planner in the depth test.
        private static let childPlannerKey = "nested-child-planner-key: plan a part"

        /// The key of the play of the grandchild planner that the depth
        /// limit refuses.
        private static let grandchildPlannerKey = "nested-grandchild-planner-key: plan a smaller part"

        /// The final text of the child planner.
        private static let childPlannerText = "The part is planned."

        /// The key of the play of the helper.
        private static let helperKey = "nested-helper-key: do one part"

        /// The final text of the helper.
        private static let helperText = "The part is done."

        /// The corrective of `start agent` at a depth limit of two.
        private static let depthLimitText = """
            You cannot start an agent here: a run that you start would be more than 2 levels deep, \
            and that is the limit. Do this part of the task yourself.
            """

        /// The start of the corrective of `start agent` at a run limit.
        private static let atLimitPrefix = "agents are working now, and that is the limit."

        /// Makes a temporary layer that holds ``agentFiles``.
        ///
        /// - Returns: The layer. The test deletes it.
        /// - Throws: The error of the file system.
        private static func makeLayer() throws -> TemporaryLayer {
            let layer = try TemporaryLayer.makeEmpty()
            for (path, text) in agentFiles {
                try layer.write(text, at: path)
            }
            return layer
        }

        @Test("with maxConcurrentAgents 2, two waiting siblings hold no place, and their children start",
            .timeLimit(.minutes(1)))
        func waitingSiblingsLetChildrenStart() async throws {
            let harness = try await AgentsToolHarness.make(
                script: ScriptedAgentScript([
                    ScriptedAgentPlay(
                        key: NestedRunTests.rootKey,
                        steps: [
                            NestedRunTests.startStep(NestedRunTests.lead, prompt: Self.firstSiblingKey),
                            NestedRunTests.startStep(NestedRunTests.lead, prompt: Self.secondSiblingKey),
                            .finalText(NestedRunTests.rootText)
                        ]),
                    NestedRunTests.parentPlay(
                        Self.firstSiblingKey,
                        children: [(NestedRunTests.reviewer, NestedRunTests.reviewerKey)]),
                    NestedRunTests.parentPlay(
                        Self.secondSiblingKey,
                        children: [(NestedRunTests.testWriter, NestedRunTests.testWriterKey)]),
                    ScriptedAgentPlay(
                        key: NestedRunTests.reviewerKey, steps: [.finalText(NestedRunTests.reviewerText)]),
                    ScriptedAgentPlay(
                        key: NestedRunTests.testWriterKey, steps: [.finalText(NestedRunTests.testWriterText)])
                ]),
                maxConcurrentAgents: Self.siblingLimit)
            defer { try? harness.delete() }
            let root = NestedRunTests.rootSession(of: harness)

            #expect(try await root.respond(to: NestedRunTests.rootPrompt) == NestedRunTests.rootText)
            let siblings = await harness.runner.runs(caller: root.id)
            let first = try #require(siblings.first)
            let second = try #require(siblings.last)
            let results = [try await first.result(), try await second.result()]
            let children = await harness.runner.runs(caller: first.id) + harness.runner.runs(caller: second.id)
            let refusals = harness.runHarness.script.toolOutputs.filter { $0.contains(Self.atLimitPrefix) }
            await root.close()

            #expect(siblings.count == Self.siblingLimit)
            #expect(children.map(\.agent.id).sorted() == [NestedRunTests.reviewer, NestedRunTests.testWriter])
            #expect(refusals.isEmpty)
            #expect(results.contains { $0.contains(NestedRunTests.reviewerText) })
            #expect(results.contains { $0.contains(NestedRunTests.testWriterText) })
        }

        @Test("with maxDepth 2, a grandchild start gives the corrective and starts no run",
            .timeLimit(.minutes(1)))
        func grandchildAboveMaxDepthGivesCorrective() async throws {
            let layer = try Self.makeLayer()
            defer { try? layer.delete() }
            let harness = try await AgentRunHarness.make(
                script: ScriptedAgentScript([
                    NestedRunTests.parentPlay(
                        NestedRunTests.leadKey, children: [(Self.planner, Self.childPlannerKey)]),
                    ScriptedAgentPlay(
                        key: Self.childPlannerKey,
                        steps: [
                            NestedRunTests.startStep(Self.planner, prompt: Self.grandchildPlannerKey),
                            .finalText(Self.childPlannerText)
                        ])
                ]),
                registry: AgentRegistry(layers: [layer.layer]))
            defer { try? harness.delete() }
            let runner = harness.makeRunner(maxDepth: Self.depthLimit)

            let parent = try await runner.start(Self.planner, prompt: NestedRunTests.leadKey)
            let result = try await parent.result()
            let child = try await NestedRunTests.onlyRun(of: runner, caller: parent.id)
            let grandchildren = await runner.runs(caller: child.id)

            #expect(child.depth == Self.depthLimit)
            #expect(child.state == .finished(Self.childPlannerText))
            #expect(grandchildren.isEmpty)
            #expect(harness.script.toolOutputs.contains(Self.depthLimitText))
            #expect(result.contains(Self.childPlannerText))
        }

        @Test("a child with no model runs on the flash slot when its parent is on flash", .timeLimit(.minutes(1)))
        func childInheritsFlashSlotOfParent() async throws {
            let layer = try Self.makeLayer()
            defer { try? layer.delete() }
            let harness = try await AgentRunHarness.make(
                script: ScriptedAgentScript([
                    NestedRunTests.parentPlay(NestedRunTests.leadKey, children: [(Self.helper, Self.helperKey)]),
                    ScriptedAgentPlay(key: Self.helperKey, steps: [.finalText(Self.helperText)])
                ]),
                registry: AgentRegistry(layers: [layer.layer]))
            defer { try? harness.delete() }
            let runner = harness.makeRunner()

            let parent = try await runner.start(Self.flashLead, prompt: NestedRunTests.leadKey)
            let result = try await parent.result()
            let child = try await NestedRunTests.onlyRun(of: runner, caller: parent.id)

            #expect(parent.slot == .flash)
            #expect(child.slot == .flash)
            #expect(result.contains(Self.helperText))
        }

        @Test("a run with no model that the host root session starts runs on defaultSlot", .timeLimit(.minutes(1)))
        func rootSessionChildRunsOnDefaultSlot() async throws {
            let layer = try Self.makeLayer()
            defer { try? layer.delete() }
            let harness = try await AgentsToolHarness.make(
                script: ScriptedAgentScript([
                    NestedRunTests.rootPlay(starting: Self.helper, prompt: Self.helperKey),
                    ScriptedAgentPlay(key: Self.helperKey, steps: [.finalText(Self.helperText)])
                ]),
                registry: AgentRegistry(layers: [layer.layer]))
            defer { try? harness.delete() }
            let root = harness.runHarness.profile.flash.makeSession(
                instructions: NestedRunTests.rootKey, tools: [harness.tool])

            #expect(try await root.respond(to: NestedRunTests.rootPrompt) == NestedRunTests.rootText)
            let child = try await NestedRunTests.onlyRun(of: harness.runner, caller: root.id)
            let result = try await child.result()
            let defaultSlot = await harness.runner.environment.defaultSlot
            await root.close()

            #expect(child.slot == defaultSlot)
            #expect(child.slot == .standard)
            #expect(child.depth == AgentRunner.hostDepth)
            #expect(result == Self.helperText)
        }
    }
}
