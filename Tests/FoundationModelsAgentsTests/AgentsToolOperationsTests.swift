@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins the four operations of the `agents` tool (plan.md §9.1): the success
/// texts, the corrective texts, the verb aliases, and the plain-text answer.
///
/// The tests call the tool outside a Router session, as a command line does,
/// thus `ToolContext.current` is `nil` and no run posts a final message. A
/// play matches by a key in the prompt of the run.
@Suite("Agents tool operations")
struct AgentsToolOperationsTests {
    /// A failure that a scripted step throws.
    private enum ScriptedFailure: Error {
        /// The model call of the step failed.
        case broken
    }

    /// The agent of the fixture library that each run starts. It runs on
    /// the `flash` slot.
    private static let reviewer = AgentRunTests.reviewer

    /// The prompt of each run. It is also the key of the play of the run.
    private static let prompt = "operations-run-key: review the diff"

    /// The final text of the play of a run.
    private static let finalText = "The diff is correct."

    /// The model-visible agents of the fixture library, in catalog order.
    private static let visibleAgents = ["code-reviewer", "internal-helper", "lead", "test-writer"]

    /// A name that no agent of the fixture library has.
    private static let unknownName = "no-such-agent"

    /// An id that no run has.
    private static let unknownID = "no-such-run"

    /// A filter that only the description of the project copy of
    /// code-reviewer holds, in a different case.
    private static let qualityFilter = "QUALITY"

    /// The line of the project copy of code-reviewer.
    private static let reviewerLine =
        "- code-reviewer: Reviews code for quality and best practices. This is the project copy."

    /// The start of each agent line: a dash and a space.
    private static let linePrefix = "- "

    /// The count of paragraphs of a `list agents` answer: the lines, then
    /// the delegation sentence.
    private static let listParagraphCount = 2

    /// A filter that no agent holds.
    private static let unmatchedFilter = "no-agent-holds-this-text"

    /// The text between the agent lines and the delegation sentence.
    private static let paragraphBreak = "\n\n"

    /// The id of the agent that the reload tests write.
    private static let writtenAgent = "written-agent"

    /// The id of the agent that the reload test removes.
    private static let removedAgent = "removed-agent"

    /// The description of the written agent before the reload.
    private static let firstDescription = "Checks the first version of the text."

    /// The description of the written agent after the reload.
    private static let secondDescription = "Checks the second version of the text."

    /// A script with one play for ``prompt``.
    ///
    /// - Parameter steps: The steps of the play.
    /// - Returns: The script.
    private static func script(_ steps: [ScriptedAgentStep]) -> ScriptedAgentScript {
        ScriptedAgentScript([ScriptedAgentPlay(key: prompt, steps: steps)])
    }

    /// The fields of a `start agent` payload.
    ///
    /// - Parameters:
    ///   - name: The name of the agent.
    ///   - prompt: The prompt of the run.
    /// - Returns: The fields.
    private static func startFields(_ name: String, prompt: String = prompt) -> [String: String] {
        ["name": name, "prompt": prompt]
    }

    /// The fields of a payload that names the run `run`.
    ///
    /// - Parameter run: The run.
    /// - Returns: The fields.
    private static func idFields(_ run: AgentRun) -> [String: String] {
        ["id": run.id.description]
    }

    /// The text of an agent file on the `flash` slot.
    ///
    /// - Parameters:
    ///   - name: The id of the agent.
    ///   - description: The description of the agent.
    /// - Returns: The file text.
    private static func agentFile(_ name: String, description: String) -> String {
        """
        ---
        name: \(name)
        description: \(description)
        model: flash
        ---
        You check the text that the prompt names.
        """
    }

    /// The path of the file of the agent `name` in a layer.
    ///
    /// - Parameter name: The id of the agent.
    /// - Returns: The relative path.
    private static func agentPath(_ name: String) -> String {
        "agents/\(name).md"
    }

    /// Gives the text of a model failure.
    ///
    /// - Parameter state: The state of a run.
    /// - Returns: The text of ``AgentRunFailure/modelFailed(_:)``, or `nil`
    ///   for each other state.
    private static func modelFailureText(_ state: AgentRunState) -> String? {
        if case .failed(.modelFailed(let text)) = state {
            return text
        }
        return nil
    }

    /// Starts one gated run of the reviewer through the tool.
    ///
    /// - Parameters:
    ///   - harness: The harness of the tool.
    ///   - gate: The gate of the play of the run.
    ///   - operation: The op of the start payload.
    /// - Returns: The answer of the start, and the run when its turn is in
    ///   the gate.
    private static func startGatedRun(
        in harness: AgentsToolHarness, gate: ScriptedGate, operation: String = "start agent"
    ) async throws -> (answer: String, run: AgentRun) {
        let answer = try await harness.call(operation, startFields(reviewer))
        await gate.waitForArrival()
        let run = try #require(await harness.runner.runs.first)
        return (answer, run)
    }

    @Test("list agents gives a line for each model-visible agent, then the delegation sentence")
    func listGivesLinesThenDelegationSentence() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await harness.call("list agents")
        let parts = answer.components(separatedBy: Self.paragraphBreak)
        let lineNames = parts.first?.split(separator: "\n").map { line in
            String(line.dropFirst(Self.linePrefix.count).prefix { $0 != ":" })
        }

        #expect(parts.count == Self.listParagraphCount)
        #expect(parts.first?.split(separator: "\n").allSatisfy { $0.hasPrefix(Self.linePrefix) } == true)
        #expect(lineNames == Self.visibleAgents)
        #expect(parts.last == AgentsToolDescription.delegationSentence)
    }

    @Test("list agents with a filter keeps the matches, and the case does not matter")
    func listFilterIgnoresCase() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await harness.call("list agents", ["filter": Self.qualityFilter])

        #expect(answer == Self.reviewerLine + Self.paragraphBreak + AgentsToolDescription.delegationSentence)
    }

    @Test("list agents with no match, and over an empty catalog, is the success No agents are available.")
    func listWithNoMatchGivesNoAgents() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }
        let (emptyHarness, layer) = try await AgentsToolHarness.makeEmpty()
        defer {
            try? emptyHarness.delete()
            try? layer.delete()
        }

        #expect(try await harness.call("list agents", ["filter": Self.unmatchedFilter]) == "No agents are available.")
        #expect(try await emptyHarness.call("list agents") == "No agents are available.")
    }

    @Test("the answer is plain text, not the JSON string that OperationTool makes")
    func answerIsPlainText() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await harness.call("list agents")

        #expect(!answer.hasPrefix("\""))
        #expect(answer.contains("\n"))
        #expect(!answer.contains("\\n"))
    }

    @Test("start agent answers with the run id at once, and check agent on the gated run returns at once",
        .timeLimit(.minutes(1)))
    func startThenCheckGatedRun() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(script: Self.script([.wait(gate), .finalText(Self.finalText)]))
        defer { try? harness.delete() }

        let (answer, run) = try await Self.startGatedRun(in: harness, gate: gate)
        let running = try await harness.call("check agent", Self.idFields(run))
        gate.open()
        _ = try await run.result()
        let finished = try await harness.call("check agent", Self.idFields(run))

        #expect(
            answer == """
                Agent code-reviewer started with the id \(run.id). \
                Ask about it with {"op": "check agent", "id": "\(run.id)"}.
                """)
        #expect(running == "Agent code-reviewer (\(run.id)) is running.")
        #expect(finished == "Agent code-reviewer (\(run.id)) finished.\n\n\(Self.finalText)")
        #expect(run.context == nil)
    }

    @Test("check agent on a failed run gives the reason")
    func checkFailedRunGivesReason() async throws {
        let harness = try await AgentsToolHarness.make(script: Self.script([.fail(ScriptedFailure.broken)]))
        defer { try? harness.delete() }

        _ = try await harness.call("start agent", Self.startFields(Self.reviewer))
        let run = try #require(await harness.runner.runs(caller: nil).first)
        let state = await run.finalState()
        let failureText = try #require(Self.modelFailureText(state))
        let answer = try await harness.call("check agent", Self.idFields(run))

        #expect(answer == "Agent code-reviewer (\(run.id)) failed: the model failed: \(failureText).")
    }

    @Test("cancel agent sends the cancel, check agent then tells cancelled, and a second cancel finds it ended",
        .timeLimit(.minutes(1)))
    func cancelThenCheckCancelledRun() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(script: Self.script([.wait(gate), .finalText(Self.finalText)]))
        defer { try? harness.delete() }

        let (_, run) = try await Self.startGatedRun(in: harness, gate: gate)
        let cancelled = try await harness.call("cancel agent", Self.idFields(run))
        #expect(await run.finalState() == .cancelled)
        let checked = try await harness.call("check agent", Self.idFields(run))
        let second = try await harness.call("cancel agent", Self.idFields(run))

        #expect(
            cancelled == """
                The cancel of Agent code-reviewer (\(run.id)) was sent (cancelled). \
                The run stops when its turn ends.
                """)
        #expect(checked == "Agent code-reviewer (\(run.id)) was cancelled.")
        #expect(
            second == """
                Agent code-reviewer (\(run.id)) ended before the cancel.

                Agent code-reviewer (\(run.id)) was cancelled.
                """)
    }

    @Test("each verb alias reaches its operation: show, run, status, stop", .timeLimit(.minutes(1)))
    func verbAliasesReachOperations() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(script: Self.script([.wait(gate), .finalText(Self.finalText)]))
        defer { try? harness.delete() }

        let shown = try await harness.call("show agents")
        let (started, run) = try await Self.startGatedRun(in: harness, gate: gate, operation: "run agent")
        let status = try await harness.call("status agent", Self.idFields(run))
        let stopped = try await harness.call("stop agent", Self.idFields(run))

        #expect(shown == (try await harness.call("list agents")))
        #expect(started.hasPrefix("Agent code-reviewer started with the id \(run.id)."))
        #expect(status == "Agent code-reviewer (\(run.id)) is running.")
        #expect(stopped.hasPrefix("The cancel of Agent code-reviewer (\(run.id)) was sent"))
        #expect(await run.finalState() == .cancelled)
    }

    @Test("start agent with an unknown name gives a corrective with the available names")
    func startUnknownNameIsCorrective() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await harness.call("start agent", Self.startFields(Self.unknownName))

        #expect(
            answer == """
                No agent has the name no-such-agent. \
                The agents that you can start are: code-reviewer, internal-helper, lead, test-writer.
                """)
        #expect(await harness.runner.runs.isEmpty)
    }

    @Test("start agent with a name outside Agent(a, b) gives a corrective with the permitted names")
    func startNameOutsideAllowedIsCorrective() async throws {
        let harness = try await AgentsToolHarness.make(allowedNames: [AgentRunTests.testWriter])
        defer { try? harness.delete() }

        let answer = try await harness.call("start agent", Self.startFields(Self.reviewer))

        #expect(
            answer == "You cannot start the agent code-reviewer. The agents that you can start are: test-writer.")
        #expect(await harness.runner.runs.isEmpty)
    }

    @Test("start agent with a blank prompt gives a corrective")
    func startBlankPromptIsCorrective() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await harness.call("start agent", Self.startFields(Self.reviewer, prompt: " \n "))

        #expect(answer == "The prompt is blank. An agent sees only its prompt, so put the full task in the prompt.")
        #expect(await harness.runner.runs.isEmpty)
    }

    @Test("check agent and cancel agent with an unknown id give a corrective with the ids of the caller")
    func unknownIDIsCorrective() async throws {
        let harness = try await AgentsToolHarness.make(script: Self.script([.finalText(Self.finalText)]))
        defer { try? harness.delete() }

        let before = try await harness.call("check agent", ["id": Self.unknownID])
        _ = try await harness.call("start agent", Self.startFields(Self.reviewer))
        let run = try #require(await harness.runner.runs(caller: nil).first)
        _ = try await run.result()
        let checked = try await harness.call("check agent", ["id": Self.unknownID])
        let cancelled = try await harness.call("cancel agent", ["id": Self.unknownID])

        #expect(before == "No run has the id no-such-run. You have no runs.")
        #expect(checked == "No run has the id no-such-run. The ids of your runs are: \(run.id).")
        #expect(cancelled == checked)
    }

    @Test("check agent with no id gives a corrective that asks for the id")
    func checkWithNoIDIsCorrective() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await harness.call("check agent")

        #expect(answer == #"Give the id of a run: {"op": "check agent", "id": "<id>"}."#)
    }

    @Test("after a reload, a changed agent runs with the new definition and a removed agent is a corrective")
    func reloadChangesAndRemovesAgents() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        for agent in [Self.writtenAgent, Self.removedAgent] {
            try layer.write(Self.agentFile(agent, description: Self.firstDescription), at: Self.agentPath(agent))
        }
        let harness = try await AgentsToolHarness.make(
            script: Self.script([.finalText(Self.finalText)]), registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }

        try layer.write(
            Self.agentFile(Self.writtenAgent, description: Self.secondDescription),
            at: Self.agentPath(Self.writtenAgent))
        try layer.remove(Self.agentPath(Self.removedAgent))
        try await harness.runHarness.registry.reload()
        let removed = try await harness.call("start agent", Self.startFields(Self.removedAgent))
        _ = try await harness.call("start agent", Self.startFields(Self.writtenAgent))
        let run = try #require(await harness.runner.runs(caller: nil).first)

        #expect(harness.tool.agentNames == [Self.removedAgent, Self.writtenAgent])
        #expect(removed == "No agent has the name removed-agent. The agents that you can start are: written-agent.")
        #expect(run.agent.description == Self.secondDescription)
        #expect(try await run.result() == Self.finalText)
    }
}
