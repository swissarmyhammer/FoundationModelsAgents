@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

/// Pins the host-driven part of `AgentRunner` (plan.md §8.1, §9.3): start,
/// the run index, the records of finished runs, `catalog()`, and `stop()`.
///
/// Each test resolves its own scripted profile, which records to its own
/// temporary folder. A play matches by a key in the prompt of the run.
@Suite("Agent runner")
struct AgentRunnerTests {
    /// The agent of the fixture library that each run starts.
    private static let reviewer = AgentRunTests.reviewer

    /// The agent of the fixture library that runs on the `standard` slot.
    /// The slots have separate models, thus a turn on each slot can wait in
    /// its gate at one time.
    private static let testWriter = AgentRunTests.testWriter

    /// The prompt of the first run. It is also the key of its play.
    private static let firstPrompt = "first-run-key: review the parser"

    /// The prompt of the second run. It is also the key of its play.
    private static let secondPrompt = "second-run-key: review the writer"

    /// The final text of the first play.
    private static let firstText = "The parser is correct."

    /// The final text of the second play.
    private static let secondText = "The writer is correct."

    /// A name that no agent of the fixture library has.
    private static let unknownName = "no-such-agent"

    /// The count of records that the retention test keeps.
    private static let retainedRunCount = 2

    /// The id of the broken fixture whose `model` matches no slot.
    private static let unknownModelAgent = "unknown-model"

    /// The `model` value of ``unknownModelAgent``.
    private static let unknownModelValue = "no-such-model"

    /// The id of the broken fixture whose `disallowedTools` names no tool.
    private static let unknownToolAgent = "unknown-disallowed-tool"

    /// The tool name of ``unknownToolAgent`` that matches no tool.
    private static let unknownToolName = "NoSuchTool"

    /// The key of the play of the parent session of the token test.
    private static let parentKey = "runner-parent-play-key"

    /// The prompt of the parent session of the token test.
    private static let parentPrompt = "Start the reviewer through the runner."

    /// The final text of the parent session of the token test.
    private static let parentText = "The parent started a reviewer."

    /// The arguments of the scripted call of the probe tool.
    private static let probeArguments = #"{"text":"start"}"#

    /// A script with one play for each of the two prompts.
    ///
    /// - Parameters:
    ///   - first: The steps of the play of ``firstPrompt``.
    ///   - second: The steps of the play of ``secondPrompt``.
    /// - Returns: The script.
    private static func script(first: [ScriptedAgentStep], second: [ScriptedAgentStep]) -> ScriptedAgentScript {
        ScriptedAgentScript([
            ScriptedAgentPlay(key: firstPrompt, steps: first),
            ScriptedAgentPlay(key: secondPrompt, steps: second)
        ])
    }

    /// A registry over the broken agent fixtures, as one project layer.
    ///
    /// - Returns: The registry. It is not loaded.
    private static func brokenRegistry() -> AgentRegistry {
        AgentRegistry(layers: [
            DotfolderStack.Layer(
                source: .project, root: FixtureLibrary.brokenAgentsDirectory.deletingLastPathComponent())
        ])
    }

    /// Gives the warnings of `catalog` about the agent `agent`.
    ///
    /// - Parameters:
    ///   - catalog: The catalog.
    ///   - agent: The id of the agent.
    /// - Returns: The message of each warning of the agent.
    private static func warnings(in catalog: AgentCatalog, about agent: String) -> [String] {
        catalog.diagnostics.filter { $0.severity == .warning && $0.agent == agent }.map(\.message)
    }

    @Test("two host-driven runs with async let finish independently with their own texts")
    func asyncLetRunsFinishIndependently() async throws {
        let harness = try await AgentRunHarness.make(
            script: Self.script(first: [.finalText(Self.firstText)], second: [.finalText(Self.secondText)]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        async let first = runner.start(Self.reviewer, prompt: Self.firstPrompt).result()
        async let second = runner.start(Self.reviewer, prompt: Self.secondPrompt).result()
        let texts = try await [first, second]

        #expect(texts == [Self.firstText, Self.secondText])
        #expect(harness.script.prompts.sorted() == [Self.firstPrompt, Self.secondPrompt])
        #expect(await runner.runs.isEmpty)
    }

    @Test("start with an unknown name throws unknownAgent with the available names")
    func unknownNameThrowsWithAvailableNames() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        await #expect(
            throws: AgentRunnerError.unknownAgent(
                name: Self.unknownName, available: FixtureLibrary.localAgentIDs.sorted())
        ) {
            try await runner.start(Self.unknownName, prompt: Self.firstPrompt)
        }
        #expect(await runner.runs.isEmpty)
    }

    @Test("before registry.load(), start throws unknownAgent with no available names")
    func unloadedRegistryHasNoAvailableNames() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let runner = AgentRunner(
            registry: AgentRegistry(stack: FixtureLibrary.stack()), environment: harness.environment)

        await #expect(throws: AgentRunnerError.unknownAgent(name: Self.reviewer, available: [])) {
            try await runner.start(Self.reviewer, prompt: Self.firstPrompt)
        }
    }

    @Test("run(id:) finds a running run, then the record of the finished run")
    func runByIDFindsRunningRunAndRecord() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: Self.script(first: [.wait(gate), .finalText(Self.firstText)], second: []))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let run = try await runner.start(Self.reviewer, prompt: Self.firstPrompt)
        await gate.waitForArrival()
        let running = try #require(await runner.run(id: run.id))
        #expect(running === run)
        #expect(running.state == .running)
        #expect(await runner.runs.map(\.id) == [run.id])
        gate.open()
        _ = try await run.result()
        let record = try #require(await runner.run(id: run.id))

        #expect(record === run)
        #expect(record.state == .finished(Self.firstText))
        #expect(record.agent.id == Self.reviewer)
        #expect(record.caller == nil)
        #expect(record.depth == AgentRunner.hostDepth)
        #expect(record.slot == .flash)
        #expect(record.heldSession == nil)
        #expect(await runner.runs.isEmpty)
    }

    @Test("with maxRetainedRuns 2, a third finished run removes the oldest record")
    func thirdFinishedRunRemovesOldestRecord() async throws {
        let prompts = [Self.firstPrompt, Self.secondPrompt, Self.firstPrompt]
        let harness = try await AgentRunHarness.make(
            script: Self.script(first: [.finalText(Self.firstText)], second: [.finalText(Self.secondText)]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner(maxRetainedRuns: Self.retainedRunCount)
        var finished: [AgentRun] = []

        for prompt in prompts {
            let run = try await runner.start(Self.reviewer, prompt: prompt)
            _ = try await run.result()
            finished.append(run)
        }

        #expect(await runner.run(id: finished[0].id) == nil)
        #expect(await runner.run(id: finished[1].id) === finished[1])
        #expect(await runner.run(id: finished[2].id) === finished[2])
        #expect(finished[2].state == .finished(Self.firstText))
    }

    @Test("catalog() has a warning for unknown-model.md and for an unknown tool name")
    func catalogHasModelAndToolWarnings() async throws {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([]), registry: Self.brokenRegistry())
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let catalog = runner.catalog()
        let registryCatalog = harness.registry.catalog()
        let modelWarnings = Self.warnings(in: catalog, about: Self.unknownModelAgent)
        let toolWarnings = Self.warnings(in: catalog, about: Self.unknownToolAgent)

        #expect(modelWarnings.count == 1)
        #expect(modelWarnings.allSatisfy { $0.contains(Self.unknownModelValue) })
        #expect(toolWarnings.count == 1)
        #expect(toolWarnings.allSatisfy { $0.contains(Self.unknownToolName) })
        #expect(Self.warnings(in: registryCatalog, about: Self.unknownModelAgent).isEmpty)
        #expect(Self.warnings(in: registryCatalog, about: Self.unknownToolAgent).isEmpty)
        #expect(catalog.definitions.map(\.id) == registryCatalog.definitions.map(\.id))
        #expect(Array(catalog.diagnostics.prefix(registryCatalog.diagnostics.count)) == registryCatalog.diagnostics)
    }

    @Test("stop() cancels two gated runs, and both reach .cancelled", .timeLimit(.minutes(1)))
    func stopCancelsGatedRuns() async throws {
        let firstGate = ScriptedGate()
        let secondGate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: Self.script(
                first: [.wait(firstGate), .finalText(Self.firstText)],
                second: [.wait(secondGate), .finalText(Self.secondText)]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()
        let first = try await runner.start(Self.reviewer, prompt: Self.firstPrompt)
        let second = try await runner.start(Self.testWriter, prompt: Self.secondPrompt)
        await firstGate.waitForArrival()
        await secondGate.waitForArrival()

        await runner.stop()

        #expect(first.state == .cancelled)
        #expect(second.state == .cancelled)
        #expect(first.heldSession == nil)
        #expect(second.heldSession == nil)
        #expect(await runner.runs.isEmpty)
        #expect(await runner.run(id: first.id) === first)
    }

    @Test("the index maps the completion token of the starting tool call to the run")
    func completionTokenFindsRun() async throws {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: Self.parentKey,
                    steps: [
                        .toolCall(name: AgentStartProbe.toolName, argumentsJSON: Self.probeArguments),
                        .finalText(Self.parentText)
                    ]),
                ScriptedAgentPlay(key: Self.firstPrompt, steps: [.finalText(Self.firstText)])
            ]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()
        let definition = try #require(harness.registry.catalog().definition(named: Self.reviewer))
        let probe = AgentStartProbe { context in
            await runner.start(
                AgentRunRequest(
                    definition: definition, prompt: Self.firstPrompt, context: context,
                    inheritedSlot: .standard, depth: AgentRunner.hostDepth, parent: nil, agentsTool: nil))
        }
        let parent = harness.profile.standard.makeSession(instructions: Self.parentKey, tools: [probe])

        #expect(try await parent.respond(to: Self.parentPrompt) == Self.parentText)
        let started = try #require(probe.started)
        let context = try #require(started.context)
        #expect(await runner.run(completionToken: context.completionToken) === started.run)
        #expect(try await started.run.result() == Self.firstText)
        #expect(await runner.run(completionToken: context.completionToken) === started.run)
        #expect(started.run.caller == parent.id)
        await parent.close()
    }
}
