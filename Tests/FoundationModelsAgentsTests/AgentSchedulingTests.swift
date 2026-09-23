@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins the scheduling rules of the runner and the `agents` tool
/// (plan.md §9.2, §9.3, §16): the run limit of `start agent`, the isolation
/// of the callers, `check agent` with no id, `cancelRuns(caller:)`, and a
/// run that finishes after its caller session closed.
///
/// A caller is a root session that calls the tool. Each root session runs on
/// the `standard` slot, and its turn ends before the test holds a child. A
/// gated child holds the generation gate of its slot for its whole turn,
/// thus each gated child at one time runs on its own slot: code-reviewer on
/// `flash`, test-writer on `standard`.
@Suite("Agent scheduling")
struct AgentSchedulingTests {
    /// The run limit of the limit tests.
    private static let limit = 2

    /// The limit of the host-start test.
    private static let singleLimit = 1

    /// The count of runs that root session A starts in the no-id test.
    private static let runCountOfA = 2

    /// The count of tool answers that the last turns of the two root
    /// sessions record.
    private static let lastAnswerCount = 2

    /// The agent on the `flash` slot.
    private static let reviewer = AgentRunTests.reviewer

    /// The agent on the `standard` slot.
    private static let testWriter = AgentRunTests.testWriter

    /// The key of the play of the first gated run of the limit test.
    private static let firstKey = "scheduling-first-run"

    /// The key of the play of the second gated run of the limit test.
    private static let secondKey = "scheduling-second-run"

    /// The key of the play of a run that answers at once.
    private static let quickKey = "scheduling-quick-run"

    /// The key of the play of the child of caller A.
    private static let childAKey = "scheduling-child-of-a"

    /// The key of the play of the child of caller B.
    private static let childBKey = "scheduling-child-of-b"

    /// The key of the play of root session A. It is its instructions.
    private static let rootAKey = "scheduling-root-a"

    /// The key of the play of root session B. It is its instructions.
    private static let rootBKey = "scheduling-root-b"

    /// The first prompt of each root session.
    private static let rootPrompt = "Give the work to an agent."

    /// The second prompt of each root session.
    private static let nextPrompt = "Tell me about your runs."

    /// The answer of each turn of a root session.
    private static let rootText = "Done."

    /// The final text of each child run.
    private static let childText = "The work is correct."

    /// The text between two blocks of a `check agent` answer with no id.
    private static let blockSeparator = "\n\n"

    /// The corrective of `start agent` at a limit of two.
    private static let limitText = """
        2 agents are working now, and that is the limit. \
        Do this part of the task yourself, or start the agent when one of them finishes.
        """

    /// The answer of `check agent` with no id for a caller with no run.
    private static let noRunsText = "You have no runs."

    /// The fields of a `start agent` payload.
    ///
    /// - Parameters:
    ///   - name: The name of the agent.
    ///   - prompt: The prompt of the run. It is also the key of its play.
    /// - Returns: The fields.
    private static func startFields(_ name: String, prompt: String) -> [String: String] {
        ["name": name, "prompt": prompt]
    }

    /// The JSON arguments of a scripted `start agent` call.
    ///
    /// - Parameters:
    ///   - name: The name of the agent.
    ///   - prompt: The prompt of the run.
    /// - Returns: The JSON text.
    private static func startArguments(_ name: String, prompt: String) -> String {
        #"{"op": "start agent", "name": "\#(name)", "prompt": "\#(prompt)"}"#
    }

    /// The JSON arguments of a scripted call that names the run `run`.
    ///
    /// - Parameters:
    ///   - operation: The op of the call.
    ///   - run: The run.
    /// - Returns: The JSON text.
    private static func idArguments(_ operation: String, of run: AgentRun) -> String {
        #"{"op": "\#(operation)", "id": "\#(run.id)"}"#
    }

    /// A scripted call of the `agents` tool.
    ///
    /// - Parameter argumentsJSON: The JSON arguments of the call.
    /// - Returns: The step.
    private static func toolStep(_ argumentsJSON: String) -> ScriptedAgentStep {
        .toolCall(name: ToolVocabulary.agentsToolName, argumentsJSON: argumentsJSON)
    }

    /// A root play that starts one child with `start agent`, then answers.
    ///
    /// - Parameters:
    ///   - key: The key of the root play. It is the instructions of the root.
    ///   - agent: The name of the child agent.
    ///   - prompt: The prompt of the child. It is the key of its play.
    /// - Returns: The play.
    private static func startingPlay(_ key: String, agent: String, prompt: String) -> ScriptedAgentPlay {
        ScriptedAgentPlay(key: key, steps: [toolStep(startArguments(agent, prompt: prompt)), .finalText(rootText)])
    }

    /// Makes a root session over the `standard` slot, with the `agents` tool
    /// of the harness.
    ///
    /// - Parameters:
    ///   - key: The key of the play of the session. It is the instructions.
    ///   - harness: The harness of the tool.
    /// - Returns: The root session.
    private static func rootSession(_ key: String, of harness: AgentsToolHarness) -> any RoutedSession {
        harness.runHarness.profile.standard.makeSession(instructions: key, tools: [harness.tool])
    }

    /// Gives the one run that a root session started.
    ///
    /// - Parameters:
    ///   - harness: The harness of the tool.
    ///   - root: The root session.
    /// - Returns: The run.
    /// - Throws: The error of `#require` when the root session started no run.
    private static func onlyRun(in harness: AgentsToolHarness, of root: any RoutedSession) async throws -> AgentRun {
        let runs = await harness.runner.runs(caller: root.id)
        #expect(runs.count == 1)
        return try #require(runs.first)
    }

    /// The `check agent` block of a run that finished with ``childText``.
    ///
    /// - Parameter run: The run.
    /// - Returns: The block.
    private static func finishedBlock(of run: AgentRun) -> String {
        "Agent code-reviewer (\(run.id)) finished.\n\n\(childText)"
    }

    @Test(
        "at a limit of two with two gated runs, a third start agent is the corrective; after one ends, a start works",
        .timeLimit(.minutes(1)))
    func limitRefusesThirdStartUntilOneFinishes() async throws {
        let flashGate = ScriptedGate()
        let standardGate = ScriptedGate()
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(key: Self.firstKey, steps: [.wait(flashGate), .finalText(Self.childText)]),
            ScriptedAgentPlay(key: Self.secondKey, steps: [.wait(standardGate), .finalText(Self.childText)]),
            ScriptedAgentPlay(key: Self.quickKey, steps: [.finalText(Self.childText)])
        ])
        let harness = try await AgentsToolHarness.make(script: script, maxConcurrentAgents: Self.limit)
        defer { try? harness.delete() }

        _ = try await harness.call("start agent", Self.startFields(Self.reviewer, prompt: Self.firstKey))
        _ = try await harness.call("start agent", Self.startFields(Self.testWriter, prompt: Self.secondKey))
        await flashGate.waitForArrival()
        await standardGate.waitForArrival()
        let refused = try await harness.call("start agent", Self.startFields(Self.reviewer, prompt: Self.quickKey))
        let workingAtLimit = await harness.runner.runs
        let first = try #require(workingAtLimit.first { $0.agent.id == Self.reviewer })
        let second = try #require(workingAtLimit.first { $0.agent.id == Self.testWriter })
        flashGate.open()
        _ = try await first.result()
        let later = try await harness.call("start agent", Self.startFields(Self.reviewer, prompt: Self.quickKey))
        let laterRun = try #require(await harness.runner.runs.first { $0 !== second })
        standardGate.open()

        #expect(refused == Self.limitText)
        #expect(workingAtLimit.count == Self.limit)
        #expect(later == "Agent code-reviewer started with the id \(laterRun.id). \(Self.checkHint(laterRun))")
        #expect(try await laterRun.result() == Self.childText)
        #expect(try await second.result() == Self.childText)
    }

    @Test("a host-driven start does not check the limit, and start agent at the limit is the corrective",
        .timeLimit(.minutes(1)))
    func hostStartIgnoresLimit() async throws {
        let flashGate = ScriptedGate()
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(key: Self.firstKey, steps: [.wait(flashGate), .finalText(Self.childText)]),
            ScriptedAgentPlay(key: Self.quickKey, steps: [.finalText(Self.childText)])
        ])
        let harness = try await AgentsToolHarness.make(script: script, maxConcurrentAgents: Self.singleLimit)
        defer { try? harness.delete() }

        _ = try await harness.call("start agent", Self.startFields(Self.reviewer, prompt: Self.firstKey))
        await flashGate.waitForArrival()
        let gated = try #require(await harness.runner.runs.first)
        let refused = try await harness.call("start agent", Self.startFields(Self.testWriter, prompt: Self.quickKey))
        let host = try await harness.runner.start(Self.testWriter, prompt: Self.quickKey)
        let hostResult = try await host.result()
        flashGate.open()

        #expect(refused.hasPrefix("1 agents are working now, and that is the limit."))
        #expect(hostResult == Self.childText)
        #expect(try await gated.result() == Self.childText)
    }

    @Test("caller B cannot check or cancel a run of caller A: each gives the unknown-id corrective",
        .timeLimit(.minutes(1)))
    func callerCannotCheckOrCancelRunOfOtherCaller() async throws {
        let gate = ScriptedGate()
        let checkArguments = ScriptedArguments()
        let cancelArguments = ScriptedArguments()
        let script = ScriptedAgentScript([
            Self.startingPlay(Self.rootAKey, agent: Self.reviewer, prompt: Self.childAKey),
            ScriptedAgentPlay(
                key: Self.rootBKey,
                steps: [
                    .deferredToolCall(name: ToolVocabulary.agentsToolName, arguments: checkArguments),
                    .deferredToolCall(name: ToolVocabulary.agentsToolName, arguments: cancelArguments),
                    .finalText(Self.rootText)
                ]),
            ScriptedAgentPlay(key: Self.childAKey, steps: [.wait(gate), .finalText(Self.childText)])
        ])
        let harness = try await AgentsToolHarness.make(script: script)
        defer { try? harness.delete() }
        let rootA = Self.rootSession(Self.rootAKey, of: harness)
        let rootB = Self.rootSession(Self.rootBKey, of: harness)

        _ = try await rootA.respond(to: Self.rootPrompt)
        await gate.waitForArrival()
        let run = try await Self.onlyRun(in: harness, of: rootA)
        checkArguments.set(Self.idArguments("check agent", of: run))
        cancelArguments.set(Self.idArguments("cancel agent", of: run))
        _ = try await rootB.respond(to: Self.rootPrompt)
        let answersOfB = Array(harness.runHarness.script.toolOutputs.suffix(Self.lastAnswerCount))
        let stateAfterB = run.state
        gate.open()
        let result = try await run.result()
        await rootA.close()
        await rootB.close()

        let corrective = "No run has the id \(run.id). You have no runs."
        #expect(answersOfB == [corrective, corrective])
        #expect(stateAfterB == .running)
        #expect(result == Self.childText)
    }

    @Test("check agent with no id gives one block for each run of the caller, and only those runs",
        .timeLimit(.minutes(1)))
    func checkWithNoIDListsOnlyRunsOfCaller() async throws {
        let checkAll = Self.toolStep(#"{"op": "check agent"}"#)
        let startChild = Self.toolStep(Self.startArguments(Self.reviewer, prompt: Self.childAKey))
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: Self.rootAKey,
                steps: [startChild, startChild, .finalText(Self.rootText), checkAll, .finalText(Self.rootText)]),
            ScriptedAgentPlay(
                key: Self.rootBKey,
                steps: [startChild, .finalText(Self.rootText), checkAll, .finalText(Self.rootText)]),
            ScriptedAgentPlay(key: Self.childAKey, steps: [.finalText(Self.childText)])
        ])
        let harness = try await AgentsToolHarness.make(script: script)
        defer { try? harness.delete() }
        let rootA = Self.rootSession(Self.rootAKey, of: harness)
        let rootB = Self.rootSession(Self.rootBKey, of: harness)

        _ = try await rootA.respond(to: Self.rootPrompt)
        _ = try await rootB.respond(to: Self.rootPrompt)
        let runsOfA = await harness.runner.runs(caller: rootA.id).sorted { $0.id < $1.id }
        let runOfB = try await Self.onlyRun(in: harness, of: rootB)
        for run in runsOfA + [runOfB] {
            _ = try await run.result()
        }
        _ = try await rootA.respond(to: Self.nextPrompt)
        _ = try await rootB.respond(to: Self.nextPrompt)
        let answers = Array(harness.runHarness.script.toolOutputs.suffix(Self.lastAnswerCount))
        let hostAnswer = try await harness.call("check agent")
        await rootA.close()
        await rootB.close()

        #expect(runsOfA.count == Self.runCountOfA)
        #expect(
            answers == [
                runsOfA.map(Self.finishedBlock).joined(separator: Self.blockSeparator),
                Self.finishedBlock(of: runOfB)
            ])
        #expect(hostAnswer == Self.noRunsText)
    }

    @Test("cancelRuns(caller:) cancels the runs of that caller only", .timeLimit(.minutes(1)))
    func cancelRunsCancelsOnlyThatCaller() async throws {
        let gateA = ScriptedGate()
        let gateB = ScriptedGate()
        let script = ScriptedAgentScript([
            Self.startingPlay(Self.rootAKey, agent: Self.reviewer, prompt: Self.childAKey),
            Self.startingPlay(Self.rootBKey, agent: Self.testWriter, prompt: Self.childBKey),
            ScriptedAgentPlay(key: Self.childAKey, steps: [.wait(gateA), .finalText(Self.childText)]),
            ScriptedAgentPlay(key: Self.childBKey, steps: [.wait(gateB), .finalText(Self.childText)])
        ])
        let harness = try await AgentsToolHarness.make(script: script)
        defer { try? harness.delete() }
        let rootA = Self.rootSession(Self.rootAKey, of: harness)
        let rootB = Self.rootSession(Self.rootBKey, of: harness)

        _ = try await rootA.respond(to: Self.rootPrompt)
        _ = try await rootB.respond(to: Self.rootPrompt)
        await gateA.waitForArrival()
        await gateB.waitForArrival()
        let runOfA = try await Self.onlyRun(in: harness, of: rootA)
        let runOfB = try await Self.onlyRun(in: harness, of: rootB)
        await harness.runner.cancelRuns(caller: rootA.id)
        let stateOfA = runOfA.state
        let stateOfB = runOfB.state
        gateB.open()
        let resultOfB = try await runOfB.result()
        await rootA.close()
        await rootB.close()

        #expect(stateOfA == .cancelled)
        #expect(stateOfB == .running)
        #expect(resultOfB == Self.childText)
    }

    @Test("a run that finishes after its caller session closed does not crash, and the runner keeps its record",
        .timeLimit(.minutes(1)))
    func runFinishesAfterCallerClosed() async throws {
        let gate = ScriptedGate()
        let script = ScriptedAgentScript([
            Self.startingPlay(Self.rootAKey, agent: Self.reviewer, prompt: Self.childAKey),
            ScriptedAgentPlay(key: Self.childAKey, steps: [.wait(gate), .finalText(Self.childText)])
        ])
        let harness = try await AgentsToolHarness.make(script: script)
        defer { try? harness.delete() }
        let rootA = Self.rootSession(Self.rootAKey, of: harness)

        _ = try await rootA.respond(to: Self.rootPrompt)
        await gate.waitForArrival()
        let run = try await Self.onlyRun(in: harness, of: rootA)
        await rootA.close()
        gate.open()
        let result = try await run.result()
        let record = await harness.runner.run(id: run.id)

        #expect(result == Self.childText)
        #expect(record?.id == run.id)
        #expect(record?.state == .finished(Self.childText))
        #expect(await harness.runner.runs.isEmpty)
    }

    /// The end of the `start agent` answer outside a Router session.
    ///
    /// - Parameter run: The run that the call started.
    /// - Returns: The sentence that tells how to ask about the run.
    private static func checkHint(_ run: AgentRun) -> String {
        #"Ask about it with {"op": "check agent", "id": "\#(run.id)"}."#
    }
}
