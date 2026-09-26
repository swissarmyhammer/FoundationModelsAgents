@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// The gates of one test of `AgentSchedulingTests.Setup`.
private struct SetupGates {
    /// Holds the setup of the lead run in the maker of its `agents` tool.
    let setup = ScriptedGate()

    /// Holds the turn of the code-reviewer run.
    let reviewer = ScriptedGate()

    /// Holds the turn of the lead run. The test never opens it.
    let lead = ScriptedGate()
}

extension AgentSchedulingTests {
    /// Pins the cancel of the starts whose setup is in operation (plan.md
    /// §9.2, §9.3): `cancelRuns(caller:)` and `stop()` wait until the setup of
    /// each start of the target ends, then cancel the run and wait for its
    /// final state. `cancelRuns(caller:)` does not wait for a start of a
    /// different caller.
    ///
    /// The setup holds in the maker of the `agents` tool of a lead run: the
    /// maker waits on a gate. The target also has a run in operation that
    /// waits in its turn. The cancel call cancels that run before it waits for
    /// the setups, thus the test knows that the call took its snapshot when
    /// that run ends. Only then the test opens the setup gate.
    ///
    /// The root session runs on the `standard` slot. The code-reviewer run
    /// and the lead run run on the `flash` slot.
    @Suite("Agent scheduling: starts in setup")
    struct Setup {
        /// The agent with `tools: Agent(...)`, thus its setup calls the maker
        /// of the `agents` tool.
        private static let lead = NestedRunTests.lead

        /// The agent of the run in operation.
        private static let reviewer = AgentRunTests.reviewer

        /// The key of the play of the root session. It is its instructions.
        private static let rootKey = "setup-root-key"

        /// The prompt of the root session.
        private static let rootPrompt = "Give the work to two agents."

        /// The answer of the root session.
        private static let rootText = "Done."

        /// The prompt of the lead run. It is also the key of its play.
        private static let leadKey = "setup-lead-key: divide the task"

        /// The prompt of the code-reviewer run. It is also the key of its play.
        private static let reviewerKey = "setup-reviewer-key: review the parser"

        /// The final text of each run that the test lets finish.
        private static let childText = "The work is correct."

        /// The corrective of `start agent` after `stop()`.
        private static let stoppedText = """
            The agent runner is stopped, and it starts no more agents. Do this part of the task yourself.
            """

        /// The arguments of the scripted call of the probe tool.
        private static let probeArguments = #"{"text":"start"}"#

        /// The arguments of the scripted `start agent` call of the root
        /// session.
        private static let startArguments =
            #"{"op": "start agent", "name": "\#(reviewer)", "prompt": "\#(reviewerKey)"}"#

        /// The step of the root session that starts the code-reviewer with
        /// `start agent`.
        private static let startStep =
            ScriptedAgentStep.toolCall(name: ToolVocabulary.agentsToolName, argumentsJSON: startArguments)

        /// The step of the root session that starts the lead with the probe
        /// tool.
        private static let probeStep =
            ScriptedAgentStep.toolCall(name: AgentStartProbe.toolName, argumentsJSON: probeArguments)

        /// Makes the script: the root session plays `rootCalls`, then
        /// answers. Each run waits on its gate.
        ///
        /// - Parameters:
        ///   - gates: The gates of the test.
        ///   - rootCalls: The tool calls of the root session.
        /// - Returns: The script.
        private static func script(_ gates: SetupGates, rootCalls: [ScriptedAgentStep]) -> ScriptedAgentScript {
            ScriptedAgentScript([
                ScriptedAgentPlay(key: rootKey, steps: rootCalls + [.finalText(rootText)]),
                ScriptedAgentPlay(key: reviewerKey, steps: [.wait(gates.reviewer), .finalText(childText)]),
                ScriptedAgentPlay(key: leadKey, steps: [.wait(gates.lead), .finalText(childText)])
            ])
        }

        /// Makes the request of a lead run whose setup waits on `gate`.
        ///
        /// - Parameters:
        ///   - harness: The harness of the tool.
        ///   - context: The context of the tool call that starts the run, or
        ///     `nil` for a host-driven run.
        ///   - gate: The gate that holds the maker of the `agents` tool.
        /// - Returns: The request.
        /// - Throws: The error of `#require` when the catalog has no lead.
        private static func leadRequest(
            in harness: AgentsToolHarness, context: ToolContext?, gate: ScriptedGate
        ) throws -> AgentRunRequest {
            let definition = try #require(harness.runHarness.registry.catalog().definition(named: lead))
            let makeTool = AgentRun.agentsTool(of: harness.runner)
            return AgentRunRequest(
                definition: definition, prompt: leadKey, context: context,
                inheritedSlot: .flash, depth: AgentRunner.hostDepth, parent: nil,
                agentsTool: { parent, allowedNames in
                    try await gate.wait()
                    return try await makeTool(parent, allowedNames)
                })
        }

        /// Gives the one run of `caller` whose agent is `agent`.
        ///
        /// - Parameters:
        ///   - agent: The id of the agent.
        ///   - caller: The id of the caller session, or `nil` for the host.
        ///   - harness: The harness of the tool.
        /// - Returns: The run.
        /// - Throws: The error of `#require` when the caller has no such run.
        private static func run(
            of agent: String, caller: ULID?, in harness: AgentsToolHarness
        ) async throws -> AgentRun {
            try #require(await harness.runner.runs(caller: caller).first { $0.agent.id == agent })
        }

        @Test(
            "cancelRuns(caller:) waits for a start of that caller in setup, and cancels it",
            .timeLimit(.minutes(1)))
        func cancelRunsCancelsStartInSetup() async throws {
            let gates = SetupGates()
            let harness = try await AgentsToolHarness.make(
                script: Self.script(gates, rootCalls: [Self.startStep, Self.probeStep]))
            defer { try? harness.delete() }
            let probe = AgentStartProbe { context in
                await harness.runner.start(try Self.leadRequest(in: harness, context: context, gate: gates.setup))
            }
            let root = harness.runHarness.profile.standard.makeSession(
                instructions: Self.rootKey, tools: [harness.tool, probe])

            async let rootAnswer = root.respond(to: Self.rootPrompt)
            await gates.reviewer.waitForArrival()
            await gates.setup.waitForArrival()
            let reviewerRun = try await Self.run(of: Self.reviewer, caller: root.id, in: harness)
            async let cancelling: Void = harness.runner.cancelRuns(caller: root.id)
            let reviewerState = await reviewerRun.finalState()
            gates.setup.open()
            await cancelling
            let leadRun = try await Self.run(of: Self.lead, caller: root.id, in: harness)
            let leadState = leadRun.state
            await harness.runner.stop()
            _ = try await rootAnswer
            await root.close()

            #expect(reviewerState == .cancelled)
            #expect(leadState == .cancelled)
        }

        @Test(
            "cancelRuns(caller:) does not wait for a start of a different caller in setup",
            .timeLimit(.minutes(1)))
        func cancelRunsLeavesSetupOfOtherCaller() async throws {
            let gates = SetupGates()
            let harness = try await AgentsToolHarness.make(script: Self.script(gates, rootCalls: [Self.startStep]))
            defer { try? harness.delete() }
            let root = harness.runHarness.profile.standard.makeSession(
                instructions: Self.rootKey, tools: [harness.tool])
            let hostRequest = try Self.leadRequest(in: harness, context: nil, gate: gates.setup)

            _ = try await root.respond(to: Self.rootPrompt)
            await gates.reviewer.waitForArrival()
            let reviewerRun = try await Self.run(of: Self.reviewer, caller: root.id, in: harness)
            async let hostStart = harness.runner.start(hostRequest)
            await gates.setup.waitForArrival()
            await harness.runner.cancelRuns(caller: root.id)
            let reviewerState = reviewerRun.state
            gates.setup.open()
            let hostRun = await hostStart
            let hostState = hostRun.state
            await harness.runner.stop()
            await root.close()

            #expect(reviewerState == .cancelled)
            #expect(hostState == .running)
            #expect(hostRun.caller == nil)
        }

        @Test("stop() waits for a start in setup, and cancels it", .timeLimit(.minutes(1)))
        func stopCancelsStartInSetup() async throws {
            let gates = SetupGates()
            let harness = try await AgentsToolHarness.make(script: Self.script(gates, rootCalls: []))
            defer { try? harness.delete() }
            let hostRequest = try Self.leadRequest(in: harness, context: nil, gate: gates.setup)

            let reviewerRun = try await harness.runner.start(Self.reviewer, prompt: Self.reviewerKey)
            await gates.reviewer.waitForArrival()
            async let hostStart = harness.runner.start(hostRequest)
            await gates.setup.waitForArrival()
            async let stopping: Void = harness.runner.stop()
            let reviewerState = await reviewerRun.finalState()
            gates.setup.open()
            await stopping
            let hostRun = await hostStart
            let hostState = hostRun.state
            await harness.runner.stop()

            #expect(reviewerState == .cancelled)
            #expect(hostState == .cancelled)
            #expect(await harness.runner.runs.isEmpty)
        }

        @Test("after stop(), start throws stopped, start agent gives the corrective, and no run starts")
        func stopRefusesLaterStarts() async throws {
            let harness = try await AgentsToolHarness.make(script: Self.script(SetupGates(), rootCalls: []))
            defer { try? harness.delete() }

            await harness.runner.stop()
            await #expect(throws: AgentRunnerError.stopped) {
                try await harness.runner.start(Self.reviewer, prompt: Self.reviewerKey)
            }
            let answer = try await harness.call("start agent", ["name": Self.reviewer, "prompt": Self.reviewerKey])

            #expect(answer == Self.stoppedText)
            #expect(await harness.runner.runs(caller: nil).isEmpty)
        }
    }
}
