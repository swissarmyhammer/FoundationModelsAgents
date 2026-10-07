@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

extension NestedRunTests {
    /// Pins the limits and the slots of nested runs (plan.md §7, §9.3): a
    /// run that waits for its children holds no place in the run limit, a
    /// run at `maxDepth` has no `agents` tool, a run of an agent with no
    /// `tools` key has no `agents` tool, a direct start above
    /// `maxDepth` gives a corrective, and `model: inherit` in a child uses
    /// the slot of the calling run.
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

        /// The key of the play of the child of the first sibling.
        private static let firstHelperKey = "nested-first-helper-key: do the first part"

        /// The final text of the child of the first sibling.
        private static let firstHelperText = "The first part is done."

        /// The key of the play of the child of the second sibling.
        private static let secondHelperKey = "nested-second-helper-key: do the second part"

        /// The final text of the child of the second sibling.
        private static let secondHelperText = "The second part is done."

        /// The key of the play of the child planner in the depth test.
        private static let childPlannerKey = "nested-child-planner-key: plan a part"

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

        /// The script of the sibling test.
        ///
        /// The root session starts ``planner`` (the second sibling, on the
        /// `standard` slot) and then ``flashLead`` (the first sibling, on the
        /// `flash` slot). Each sibling starts one ``helper``, which runs on
        /// the slot of its sibling. The task answer of the second sibling
        /// waits on a gate before its `start agent` call, and each helper
        /// waits on a gate. A gated submission holds the generation queue of
        /// its model, thus each gated submission at one time is on its own
        /// model. The root answers the mail of each sibling.
        ///
        /// - Parameters:
        ///   - secondSibling: Holds the task turn of the second sibling
        ///     before its `start agent` call.
        ///   - firstChild: Holds the turn of the child of the first sibling.
        ///   - secondChild: Holds the turn of the child of the second
        ///     sibling.
        /// - Returns: The script.
        private static func siblingScript(
            secondSibling: ScriptedGate, firstChild: ScriptedGate, secondChild: ScriptedGate
        ) -> ScriptedAgentScript {
            let secondSiblingPlay = NestedRunTests.parentPlay(
                secondSiblingKey, children: [(helper, secondHelperKey)])
            return ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: NestedRunTests.rootKey,
                    steps: [
                        NestedRunTests.startStep(planner, prompt: secondSiblingKey),
                        NestedRunTests.startStep(flashLead, prompt: firstSiblingKey),
                        .finalText(NestedRunTests.rootText),
                        .finalTextOfLastPrompt,
                        .finalTextOfLastPrompt
                    ]),
                NestedRunTests.parentPlay(firstSiblingKey, children: [(helper, firstHelperKey)]),
                ScriptedAgentPlay(key: secondSiblingKey, steps: [.wait(secondSibling)] + secondSiblingPlay.steps),
                ScriptedAgentPlay(key: firstHelperKey, steps: [.wait(firstChild), .finalText(firstHelperText)]),
                ScriptedAgentPlay(key: secondHelperKey, steps: [.wait(secondChild), .finalText(secondHelperText)])
            ])
        }

        /// Waits until `run` waits for its children, or until it ended.
        ///
        /// - Parameter run: A sibling run.
        /// - Throws: `CancellationError` when the test is cancelled.
        private static func waitingPhase(of run: AgentRun) async throws {
            while run.state == .running && run.phase != .waitingForChildren {
                try await Task.sleep(for: NestedRunTests.pollInterval)
            }
        }

        @Test("with maxConcurrentAgents 2, two waiting siblings hold no place, and their children start",
            .timeLimit(.minutes(1)))
        func waitingSiblingsLetChildrenStart() async throws {
            let secondSiblingGate = ScriptedGate()
            let firstChildGate = ScriptedGate()
            let secondChildGate = ScriptedGate()
            let layer = try Self.makeLayer()
            defer { try? layer.delete() }
            let harness = try await AgentsToolHarness.make(
                script: Self.siblingScript(
                    secondSibling: secondSiblingGate, firstChild: firstChildGate, secondChild: secondChildGate),
                registry: AgentRegistry(layers: [layer.layer]),
                maxConcurrentAgents: Self.siblingLimit)
            defer { try? harness.delete() }
            let root = NestedRunTests.rootSession(of: harness)

            #expect(try await root.respond(to: NestedRunTests.rootPrompt) == NestedRunTests.rootText)
            await secondSiblingGate.waitForArrival()
            await firstChildGate.waitForArrival()
            // The Router answers each start agent call before its body adds
            // the run. Wait until the body of each call added its run.
            await harness.tool.context.startedRuns.waitForStarts()
            let siblings = await harness.runner.runs(caller: root.id)
            let first = try #require(siblings.first { $0.agent.id == Self.flashLead })
            let second = try #require(siblings.first { $0.agent.id == Self.planner })
            try await Self.waitingPhase(of: first)
            let firstPhase = first.phase
            secondSiblingGate.open()
            try await Self.waitingPhase(of: second)
            let secondPhase = second.phase
            firstChildGate.open()
            secondChildGate.open()
            let firstResult = try await first.result()
            let secondResult = try await second.result()
            let children = await harness.runner.runs(caller: first.id) + harness.runner.runs(caller: second.id)
            let refusals = harness.runHarness.script.toolOutputs.filter { $0.contains(Self.atLimitPrefix) }
            await root.close()

            #expect(siblings.count == Self.siblingLimit)
            #expect(firstPhase == .waitingForChildren)
            #expect(secondPhase == .waitingForChildren)
            #expect(children.map(\.agent.id) == [Self.helper, Self.helper])
            #expect(refusals.isEmpty)
            #expect(firstResult.contains(Self.firstHelperText))
            #expect(secondResult.contains(Self.secondHelperText))
        }

        @Test("with maxDepth 2, the child at the limit has no agents tool, and its parent has one",
            .timeLimit(.minutes(1)))
        func childAtMaxDepthHasNoAgentsTool() async throws {
            let layer = try Self.makeLayer()
            defer { try? layer.delete() }
            let harness = try await AgentRunHarness.make(
                script: ScriptedAgentScript([
                    NestedRunTests.parentPlay(
                        NestedRunTests.leadKey, children: [(Self.planner, Self.childPlannerKey)]),
                    ScriptedAgentPlay(key: Self.childPlannerKey, steps: [.finalText(Self.childPlannerText)])
                ]),
                registry: AgentRegistry(layers: [layer.layer]))
            defer { try? harness.delete() }
            let runner = harness.makeRunner(maxDepth: Self.depthLimit)

            let parent = try await runner.start(Self.planner, prompt: NestedRunTests.leadKey)
            let result = try await parent.result()
            let child = try await NestedRunTests.onlyRun(of: runner, caller: parent.id)

            #expect(child.depth == Self.depthLimit)
            #expect(harness.script.toolNames(ofPlay: NestedRunTests.leadKey) == [ToolVocabulary.agentsToolName])
            #expect(harness.script.toolNames(ofPlay: Self.childPlannerKey) == [])
            #expect(child.state == .finished(Self.childPlannerText))
            #expect(result.contains(Self.childPlannerText))
        }

        @Test("an agent with no tools key gets no agents tool, and an agent with tools: Agent gets one",
            .timeLimit(.minutes(1)))
        func noToolsKeyGivesNoAgentsTool() async throws {
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

            let parent = try await runner.start(Self.planner, prompt: NestedRunTests.leadKey)
            let result = try await parent.result()

            #expect(harness.script.toolNames(ofPlay: NestedRunTests.leadKey) == [ToolVocabulary.agentsToolName])
            #expect(harness.script.toolNames(ofPlay: Self.helperKey) == [])
            #expect(result.contains(Self.helperText))
        }

        @Test("with maxDepth 2, a direct start agent call for a run at the limit gives the corrective")
        func directStartAboveMaxDepthGivesCorrective() async throws {
            let layer = try Self.makeLayer()
            defer { try? layer.delete() }
            let runHarness = try await AgentRunHarness.make(
                script: ScriptedAgentScript([]), registry: AgentRegistry(layers: [layer.layer]))
            defer { try? runHarness.delete() }
            let runner = runHarness.makeRunner(maxDepth: Self.depthLimit)
            let atLimit = ParentRun(depth: Self.depthLimit, slot: .standard, family: ParentRun.Family())
            let tool = try await AgentsTool.make(
                context: AgentsToolContext(
                    runner: runner, allowedNames: nil, parent: atLimit, callerLink: nil, grant: .full))
            let harness = AgentsToolHarness(runHarness: runHarness, runner: runner, tool: tool)

            let answer = try await harness.call("start agent", ["name": Self.helper, "prompt": Self.helperKey])

            #expect(answer == Self.depthLimitText)
            #expect(await runner.runs.isEmpty)
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
            let events = await root.streamSessionEvents()

            #expect(try await root.respond(to: NestedRunTests.rootPrompt) == NestedRunTests.rootText)
            _ = try await NestedRunTests.firstSettlement(in: events)
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
