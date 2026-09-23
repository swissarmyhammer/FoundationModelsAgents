@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins the `maxTurns` count (plan.md §5, §9.3): one turn is one pass of
/// the control loop. Each pass records one `.toolCalls` or `.response`
/// entry, and the count holds the passes of the task turn and of each
/// delivery turn. Above the limit the run fails with `hitMaxTurns` and the
/// text so far.
///
/// The runs and the root sessions are on the `standard` slot. A gated child
/// is on the `flash` slot, thus its turn does not hold the generation gate
/// of its parent.
@Suite("maxTurns")
struct MaxTurnsTests {
    /// The `maxTurns` limit of ``limited`` and ``limitedLead``.
    private static let turnLimit = 2

    /// The count of tool passes before the answer in the test of a run with
    /// no limit.
    private static let manyToolPasses = 12

    /// The count of tool calls in the one pass of the parallel-call test.
    private static let callsInOnePass = 3

    /// The count of passes of a task turn with two tool passes and one
    /// answer.
    private static let twoToolsAndAnswer = 3

    /// The count of passes of a task turn with one tool pass and one answer.
    private static let oneToolAndAnswer = 2

    /// The count of passes of a lead that starts one child in its task turn,
    /// answers, and answers one delivery turn.
    private static let leadPasses = 3

    /// The count of answer passes of one turn.
    private static let answerPasses = 1

    /// The word of the `hitMaxTurns` reason that names the limit.
    private static let limitKey = "maxTurns"

    /// The agent with `maxTurns: 2` and no `tools` key.
    private static let limited = "limited"

    /// The agent with no `maxTurns` and no `tools` key.
    private static let unlimited = "unlimited"

    /// The agent with `maxTurns: 2` that can start ``flashHelper``.
    private static let limitedLead = "limited-lead"

    /// The agent with no `maxTurns` that can start ``flashHelper``.
    private static let countingLead = "counting-lead"

    /// The agent on the `flash` slot that the leads start.
    private static let flashHelper = "flash-helper"

    /// The agent files of the temporary layer, by path.
    private static let agentFiles = [
        "agents/\(limited).md": """
            ---
            name: \(limited)
            description: Does a task in a small count of turns.
            maxTurns: \(turnLimit)
            ---

            You work in a small count of turns.
            """,
        "agents/\(unlimited).md": """
            ---
            name: \(unlimited)
            description: Does a task in any count of turns.
            ---

            You work in any count of turns.
            """,
        "agents/\(limitedLead).md": """
            ---
            name: \(limitedLead)
            description: Gives a part of a task to the helper in a small count of turns.
            maxTurns: \(turnLimit)
            tools: Agent(\(flashHelper))
            ---

            You are a lead with a small count of turns.
            """,
        "agents/\(countingLead).md": """
            ---
            name: \(countingLead)
            description: Gives a part of a task to the helper.
            tools: Agent(\(flashHelper))
            ---

            You are a lead.
            """,
        "agents/\(flashHelper).md": """
            ---
            name: \(flashHelper)
            description: Does one part of a task on the flash slot.
            model: flash
            ---

            You are a helper on the flash slot.
            """
    ]

    /// The arguments of one `list agents` call.
    private static let listArguments = #"{"op": "list agents"}"#

    /// A pass that calls `list agents` one time.
    private static let listStep = ScriptedAgentStep.toolCall(
        name: ToolVocabulary.agentsToolName, argumentsJSON: listArguments)

    /// The key of the play of the task-turn tests.
    private static let taskKey = "max-turns-task-key: count the passes"

    /// The key of the play of the lead in the delivery tests.
    private static let leadKey = "max-turns-lead-key: give the part to the helper"

    /// The key of the play of the helper.
    private static let helperKey = "max-turns-helper-key: do the part"

    /// The answer of a run in the task-turn tests.
    private static let answerText = "The task is done."

    /// The answer of the task turn of a lead.
    private static let leadText = "I started the helper."

    /// The answer of the helper.
    private static let helperText = "The part is done."

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

    /// Starts a host-driven run of `agent` with `prompt` over the agents of
    /// ``agentFiles``, and waits for it to end.
    ///
    /// - Parameters:
    ///   - agent: The agent of the temporary layer.
    ///   - prompt: The prompt of the run. It is the key of its play.
    ///   - plays: The plays of the script.
    /// - Returns: The run and its final state.
    /// - Throws: The error of the file system, of the harness, or of
    ///   `runner.start`.
    private static func finishedRun(
        of agent: String, prompt: String, plays: [ScriptedAgentPlay]
    ) async throws -> (run: AgentRun, final: AgentRunState) {
        let layer = try makeLayer()
        defer { try? layer.delete() }
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript(plays), registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }
        let run = try await harness.makeRunner().start(agent, prompt: prompt)
        return (run, await run.finalState())
    }

    /// Starts a host-driven run of `agent` that plays `steps` in its task
    /// turn, and waits for it to end.
    ///
    /// - Parameters:
    ///   - agent: The agent of the temporary layer.
    ///   - steps: The steps of the play of the run.
    /// - Returns: The run and its final state.
    /// - Throws: The error of ``finishedRun(of:prompt:plays:)``.
    private static func finishedRun(
        of agent: String, playing steps: [ScriptedAgentStep]
    ) async throws -> (run: AgentRun, final: AgentRunState) {
        try await finishedRun(of: agent, prompt: taskKey, plays: [ScriptedAgentPlay(key: taskKey, steps: steps)])
    }

    /// Starts a host-driven run of `lead`. The lead starts ``flashHelper``
    /// in its task turn, answers, and then answers one delivery turn with
    /// the prompt that it read.
    ///
    /// - Parameter lead: ``limitedLead`` or ``countingLead``.
    /// - Returns: The run and its final state.
    /// - Throws: The error of ``finishedRun(of:prompt:plays:)``.
    private static func finishedLead(_ lead: String) async throws -> (run: AgentRun, final: AgentRunState) {
        try await finishedRun(
            of: lead,
            prompt: leadKey,
            plays: [
                ScriptedAgentPlay(
                    key: leadKey,
                    steps: [
                        NestedRunTests.startStep(flashHelper, prompt: helperKey),
                        .finalText(leadText),
                        .finalTextOfLaterPrompts
                    ]),
                ScriptedAgentPlay(key: helperKey, steps: [.finalText(helperText)])
            ])
    }

    /// Gives the partial text of a ``AgentRunFailure/hitMaxTurns(partial:)``
    /// failure.
    ///
    /// - Parameter state: The final state of a run.
    /// - Returns: The partial text, or `nil` for each other state.
    private static func partialText(of state: AgentRunState) -> String? {
        if case .failed(.hitMaxTurns(let partial)) = state {
            return partial
        }
        return nil
    }

    @Test("a task turn with two tool passes and one answer counts 3", .timeLimit(.minutes(1)))
    func twoToolPassesAndAnswerCountThree() async throws {
        let ended = try await Self.finishedRun(
            of: Self.unlimited, playing: [Self.listStep, Self.listStep, .finalText(Self.answerText)])

        #expect(ended.final == .finished(Self.answerText))
        #expect(ended.run.turns.count == Self.twoToolsAndAnswer)
    }

    @Test("one pass that calls three tools counts 1", .timeLimit(.minutes(1)))
    func threeToolsInOnePassCountOne() async throws {
        let ended = try await Self.finishedRun(
            of: Self.limited,
            playing: [
                .repeatedToolCall(
                    name: ToolVocabulary.agentsToolName, argumentsJSON: Self.listArguments,
                    count: Self.callsInOnePass),
                .finalText(Self.answerText)
            ])

        #expect(ended.final == .finished(Self.answerText))
        #expect(ended.run.turns.count == Self.oneToolAndAnswer)
    }

    @Test("maxTurns 2 with a script of three passes fails with hitMaxTurns and the partial text",
        .timeLimit(.minutes(1)))
    func threePassesAboveLimitFail() async throws {
        let ended = try await Self.finishedRun(
            of: Self.limited, playing: [Self.listStep, Self.listStep, .finalText(Self.answerText)])

        #expect(ended.final == .failed(.hitMaxTurns(partial: Self.answerText)))
        #expect(ended.run.turns.count == Self.turnLimit + Self.answerPasses)
        #expect(ended.run.report.contains(Self.limitKey))
    }

    @Test("the passes of a delivery turn add to the same count", .timeLimit(.minutes(1)))
    func deliveryPassesAddToCount() async throws {
        let ended = try await Self.finishedLead(Self.countingLead)
        let result = try await ended.run.result()

        #expect(ended.run.turns.count == Self.leadPasses)
        #expect(result.contains(Self.helperText))
    }

    @Test("a lead with maxTurns 2 fails in its delivery turn with the text of that turn",
        .timeLimit(.minutes(1)))
    func deliveryPassAboveLimitFails() async throws {
        let ended = try await Self.finishedLead(Self.limitedLead)
        let partial = Self.partialText(of: ended.final)

        #expect(partial?.contains(Self.helperText) == true)
        #expect(ended.run.turns.count == Self.leadPasses)
    }

    @Test("a run with no maxTurns finishes with any count of passes", .timeLimit(.minutes(1)))
    func noLimitFinishesWithManyPasses() async throws {
        let steps = [ScriptedAgentStep](repeating: Self.listStep, count: Self.manyToolPasses)
        let ended = try await Self.finishedRun(of: Self.unlimited, playing: steps + [.finalText(Self.answerText)])

        #expect(ended.final == .finished(Self.answerText))
        #expect(ended.run.turns.count == Self.manyToolPasses + Self.answerPasses)
    }

    @Test("a hitMaxTurns run with an open child cancels the child first, then posts one .completed",
        .timeLimit(.minutes(1)))
    func hitMaxTurnsCancelsOpenChildThenPosts() async throws {
        let gate = ScriptedGate()
        let layer = try Self.makeLayer()
        defer { try? layer.delete() }
        let harness = try await AgentsToolHarness.make(
            script: ScriptedAgentScript([
                NestedRunTests.rootPlay(starting: Self.limitedLead, prompt: Self.leadKey),
                ScriptedAgentPlay(
                    key: Self.leadKey,
                    steps: [
                        NestedRunTests.startStep(Self.flashHelper, prompt: Self.helperKey),
                        Self.listStep,
                        .finalText(Self.leadText)
                    ]),
                ScriptedAgentPlay(key: Self.helperKey, steps: [.wait(gate), .finalText(Self.helperText)])
            ]),
            registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }
        let root = NestedRunTests.rootSession(of: harness)

        #expect(try await root.respond(to: NestedRunTests.rootPrompt) == NestedRunTests.rootText)
        let lead = try await NestedRunTests.onlyRun(of: harness.runner, caller: root.id)
        let leadFinal = await lead.finalState()
        let child = try await NestedRunTests.onlyRun(of: harness.runner, caller: lead.id)
        let childStateAtParentEnd = child.state
        let leadPosts = try NestedRunTests.posts(of: lead, in: root.recordingDirectory)
        let childPosts = try NestedRunTests.posts(of: child, in: lead.recordingDirectory)
        await root.close()

        #expect(leadFinal == .failed(.hitMaxTurns(partial: Self.leadText)))
        #expect(childStateAtParentEnd == .cancelled)
        #expect(childPosts.map(\.outcome) == [.cancelled])
        #expect(leadPosts.map(\.outcome) == [.failed])
        #expect(leadPosts.first?.detail == lead.report)
    }
}
