import FoundationModels
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Synchronization
import Testing
import ULID

/// Pins the questions of a run that its parent answers (elicitation tasks 45
/// and 46).
///
/// The root session of the host is interactive and has the `agents` tool. Its
/// `start agent` call starts a run, and the session of that run takes the
/// user presence of the root. The tool of the run asks one question. The run
/// sends the question one level up with `SubagentQuestionRelay`, thus the
/// root gets it as `elicitationRequested`, with the same id and the path of
/// the agents. An answer at the root goes down to the run that asked. Each
/// end of the question with no answer gives one `elicitationEnded` at each
/// level.
///
/// The tests read the order of the events of the root and of the runs. They
/// use no clock: the tool of the run waits for the answer, and the test acts
/// after it read the question at the root.
@Suite("Relayed questions")
struct RelayedQuestionTests {
    /// The name of the tool that asks.
    private static let askToolName = "ask"

    /// The agent whose tool asks.
    private static let asker = "relay-asker"

    /// The agent that starts ``asker``. It is the middle level of the
    /// two-level test.
    private static let lead = "relay-lead"

    /// The instructions of the root session. It is also the key of its play.
    private static let rootKey = "relay-root-key"

    /// The first prompt of the root session.
    private static let rootPrompt = "Give the work to an agent."

    /// The answer of the root to its first prompt.
    private static let rootText = "I started an agent."

    /// The key of the play of the asker.
    private static let askerKey = "relay-asker-key: ask the user"

    /// The key of the play of the lead.
    private static let leadKey = "relay-lead-key: give the task to the asker"

    /// The answer of the asker after its tool gave the answer.
    private static let askerText = "The asker is done."

    /// The answer of the asker to the mail of the answer of its question.
    private static let afterAnswerText = "I read the answer."

    /// The answer that the root gives to the question.
    private static let accept = ElicitationResponse.accept(content: [:])

    /// The agent files of the temporary layer, by path.
    private static let agentFiles = [
        AgentDocumentPath.of(asker): """
            ---
            name: \(asker)
            description: Asks the user one question.
            tools: \(askToolName)
            ---

            You ask the user.
            """,
        AgentDocumentPath.of(lead): """
            ---
            name: \(lead)
            description: Gives a task to the asker.
            tools: Agent(\(asker))
            ---

            You are a lead.
            """,
    ]

    /// The step of the asker that calls the asking tool.
    private static let askStep = ScriptedAgentStep.toolCall(
        name: askToolName, argumentsJSON: #"{"text": "parser.swift"}"#)

    /// The play of the asker: it asks, answers ``askerText`` when its tool
    /// ends, then answers the mail of the answer with ``afterAnswerText``.
    private static let askerPlay = ScriptedAgentPlay(
        key: askerKey, steps: [askStep, .finalText(askerText), .finalText(afterAnswerText)])

    /// The play of the root: it starts `name`, answers ``rootText``, then
    /// answers each mail with the text of its last prompt.
    ///
    /// - Parameters:
    ///   - name: The agent that the root starts.
    ///   - prompt: The prompt of that run.
    /// - Returns: The play.
    private static func rootPlay(starting name: String, prompt: String) -> ScriptedAgentPlay {
        ScriptedAgentPlay(
            key: rootKey,
            steps: [NestedRunTests.startStep(name, prompt: prompt), .finalText(rootText)]
                + [ScriptedAgentStep](repeating: .finalTextOfLastPrompt, count: 3))
    }

    /// The ids of the `elicitationEnded` events of the sessions of the runs
    /// of one agent.
    ///
    /// A class, because the observer and the test share it. A `Mutex` guards
    /// the ids, thus the `Sendable` conformance is compiler-checked.
    private final class EndRecord: Sendable {
        /// The agent whose runs the record reads.
        private let agent: String

        /// The ids, in the order of the events.
        private let ids = Mutex<[ULID]>([])

        /// Makes an empty record.
        ///
        /// - Parameter agent: The agent whose runs the record reads.
        init(agent: String) {
            self.agent = agent
        }

        /// The ids so far.
        var all: [ULID] {
            ids.withLock { $0 }
        }

        /// Adds the id of `output` when it is an `elicitationEnded` event of
        /// a run of the agent.
        ///
        /// - Parameters:
        ///   - run: The run of the event.
        ///   - output: A session output of that run.
        func observe(_ run: AgentRun, _ output: SessionOutput) {
            if run.agent.id == agent, case .elicitationEnded(let end) = output.event {
                ids.withLock { $0.append(end.elicitationId) }
            }
        }
    }

    /// The parts of one test.
    private struct Parts {
        /// The interactive root session with the `agents` tool.
        let root: any RoutedSession

        /// The runner of the runs of the root.
        let runner: AgentRunner

        /// The answers that the asking tool got.
        let answers: AskedAnswers

        /// The ends of the questions in the sessions of the asker.
        let askerEnds: EndRecord

        /// The ends of the questions in the sessions of the lead.
        let leadEnds: EndRecord
    }

    /// Makes a temporary layer with ``agentFiles``, a harness with the asking
    /// tool, and an interactive root session with the `agents` tool. Then it
    /// runs `body`, closes the root, and deletes the folders. It closes the
    /// root also when `body` throws: the close cancels each run of the root,
    /// thus no run of the test stays open.
    ///
    /// - Parameters:
    ///   - plays: The plays of the script.
    ///   - body: The test.
    /// - Throws: The error of the setup, or of `body`.
    private static func withParts(plays: [ScriptedAgentPlay], _ body: (Parts) async throws -> Void) async throws {
        let answers = AskedAnswers()
        let askerEnds = EndRecord(agent: asker)
        let leadEnds = EndRecord(agent: lead)
        var tools = ToolCatalog()
        tools.register(askToolName) {
            AskingTool(name: askToolName, answers: answers)
        }
        try await AgentRunHarness.withLayer(
            holding: agentFiles, plays: plays, tools: tools,
            runEventObserver: { run, output in
                askerEnds.observe(run, output)
                leadEnds.observe(run, output)
            }
        ) { harness in
            let runner = harness.makeRunner()
            let agentsTool = try await AgentsTool.make(context: AgentsToolContext(runner: runner))
            let root = AgentRunHarness.makeRootSession(
                on: harness.profile.standard, instructions: rootKey, tools: [agentsTool], userPresence: .interactive)
            do {
                try await body(
                    Parts(root: root, runner: runner, answers: answers, askerEnds: askerEnds, leadEnds: leadEnds))
            } catch {
                await root.close()
                throw error
            }
            await root.close()
        }
    }

    /// Reads `events` up to the first question, and gives it. It stops with
    /// `nil` at the first event that ends the work of the root before a
    /// question came: the end of the run of a call (`runSettled`, `lost`),
    /// the cancel of a mail, or a failed answer. It also stops at the end of
    /// the stream, when the root closed. Then no question can come.
    ///
    /// - Parameter events: The iterator of the session events of the root.
    /// - Returns: The question, or `nil`.
    private static func firstQuestion(
        in events: inout AsyncStream<SessionOutput>.Iterator
    ) async -> ElicitationRequest? {
        while let output = await events.next() {
            switch output.event {
            case .elicitationRequested(let operation):
                return operation.elicitation
            case .runSettled, .lost, .cancelled, .answerFailed:
                return nil
            default:
                continue
            }
        }
        return nil
    }

    /// Reads `events` to their end, and gives the id of each
    /// `elicitationEnded` event. Call it after the root closed.
    ///
    /// - Parameter events: The iterator of the session events of the root.
    /// - Returns: The ids, in the order of the events.
    private static func ends(in events: inout AsyncStream<SessionOutput>.Iterator) async -> [ULID] {
        var ids: [ULID] = []
        while let output = await events.next() {
            if case .elicitationEnded(let end) = output.event {
                ids.append(end.elicitationId)
            }
        }
        return ids
    }

    /// Sends the first prompt to the root of `parts`, waits until the root
    /// got the question of the asker, and gives the question and the run of
    /// the root.
    ///
    /// - Parameters:
    ///   - parts: The parts of the test.
    ///   - events: The iterator of the session events of the root, made
    ///     before the first prompt.
    /// - Returns: The question and the one run of the root.
    /// - Throws: The error of `send`, or of `#require` when no question came.
    private static func question(
        of parts: Parts, events: inout AsyncStream<SessionOutput>.Iterator
    ) async throws -> (question: ElicitationRequest, run: AgentRun) {
        try parts.root.send(rootPrompt)
        let question = try #require(await firstQuestion(in: &events))
        let run = try await NestedRunTests.onlyRun(of: parts.runner, caller: parts.root.id)
        return (question, run)
    }

    // MARK: - Task 45: the question goes up, and the answer goes down

    @Test("a question of a child goes to the root with the same id and the agent path, and the answer goes down")
    func rootAnswerReachesTheChild() async throws {
        let plays = [Self.rootPlay(starting: Self.asker, prompt: Self.askerKey), Self.askerPlay]
        try await Self.withParts(plays: plays) { parts in
            var events = await parts.root.streamSessionEvents().makeAsyncIterator()
            let (question, child) = try await Self.question(of: parts, events: &events)
            let delivery = await parts.root.respond(
                elicitationId: question.elicitationId.ulidString, response: Self.accept)
            try #require(delivery == .delivered)
            let final = await child.finalState()
            await parts.root.close()
            let rootEnds = await Self.ends(in: &events)

            #expect(question.agentPath == [Self.asker])
            #expect(question.message == AskingTool.question)
            #expect(parts.answers.all == [Self.accept])
            #expect(final == .finished(Self.afterAnswerText))
            #expect(rootEnds.isEmpty)
            #expect(parts.askerEnds.all.isEmpty)
        }
    }

    @Test("a question two levels down goes to the root with each agent in the path, and the answer goes down")
    func rootAnswerReachesTheGrandchild() async throws {
        let plays = [
            Self.rootPlay(starting: Self.lead, prompt: Self.leadKey),
            NestedRunTests.parentPlay(Self.leadKey, children: [(Self.asker, Self.askerKey)]),
            Self.askerPlay,
        ]
        try await Self.withParts(plays: plays) { parts in
            var events = await parts.root.streamSessionEvents().makeAsyncIterator()
            let (question, lead) = try await Self.question(of: parts, events: &events)
            let asker = try await NestedRunTests.onlyRun(of: parts.runner, caller: lead.id)
            let delivery = await parts.root.respond(
                elicitationId: question.elicitationId.ulidString, response: Self.accept)
            try #require(delivery == .delivered)
            let askerFinal = await asker.finalState()
            let leadFinal = await lead.finalState()

            #expect(question.agentPath == [Self.lead, Self.asker])
            #expect(parts.answers.all == [Self.accept])
            #expect(askerFinal == .finished(Self.afterAnswerText))
            if case .finished = leadFinal {
            } else {
                Issue.record("The lead did not finish: \(leadFinal)")
            }
            #expect(parts.leadEnds.all.isEmpty)
        }
    }

    // MARK: - Task 46: each end with no answer ends the question one time at each level

    @Test("a cancel of the child that asked ends the question one time at the child and one time at the root")
    func childCancelEndsEachLevelOnce() async throws {
        let plays = [Self.rootPlay(starting: Self.asker, prompt: Self.askerKey), Self.askerPlay]
        try await Self.withParts(plays: plays) { parts in
            var events = await parts.root.streamSessionEvents().makeAsyncIterator()
            let (question, child) = try await Self.question(of: parts, events: &events)
            child.cancel()
            let final = await child.finalState()
            await parts.root.close()
            let rootEnds = await Self.ends(in: &events)

            #expect(final == .cancelled)
            #expect(parts.askerEnds.all == [question.elicitationId])
            #expect(rootEnds == [question.elicitationId])
        }
    }

    @Test("cancelAll of the root ends the question one time at the root and one time at the child")
    func rootCancelAllEndsEachLevelOnce() async throws {
        let plays = [Self.rootPlay(starting: Self.asker, prompt: Self.askerKey), Self.askerPlay]
        try await Self.withParts(plays: plays) { parts in
            var events = await parts.root.streamSessionEvents().makeAsyncIterator()
            let (question, child) = try await Self.question(of: parts, events: &events)
            parts.root.cancelAll()
            let final = await child.finalState()
            await parts.root.close()
            let rootEnds = await Self.ends(in: &events)

            #expect(final == .cancelled)
            #expect(parts.askerEnds.all == [question.elicitationId])
            #expect(rootEnds == [question.elicitationId])
        }
    }

    @Test("close of the root ends the question one time at the root and one time at the child")
    func rootCloseEndsEachLevelOnce() async throws {
        let plays = [Self.rootPlay(starting: Self.asker, prompt: Self.askerKey), Self.askerPlay]
        try await Self.withParts(plays: plays) { parts in
            var events = await parts.root.streamSessionEvents().makeAsyncIterator()
            let (question, child) = try await Self.question(of: parts, events: &events)
            await parts.root.close()
            let final = await child.finalState()
            let rootEnds = await Self.ends(in: &events)

            #expect(final == .cancelled)
            #expect(parts.askerEnds.all == [question.elicitationId])
            #expect(rootEnds == [question.elicitationId])
        }
    }

    @Test("a cancel of the middle run ends the question one time at each of the three levels")
    func middleCancelEndsEachLevelOnce() async throws {
        let plays = [
            Self.rootPlay(starting: Self.lead, prompt: Self.leadKey),
            NestedRunTests.parentPlay(Self.leadKey, children: [(Self.asker, Self.askerKey)]),
            Self.askerPlay,
        ]
        try await Self.withParts(plays: plays) { parts in
            var events = await parts.root.streamSessionEvents().makeAsyncIterator()
            let (question, lead) = try await Self.question(of: parts, events: &events)
            let asker = try await NestedRunTests.onlyRun(of: parts.runner, caller: lead.id)
            lead.cancel()
            let leadFinal = await lead.finalState()
            let askerFinal = await asker.finalState()
            await parts.root.close()
            let rootEnds = await Self.ends(in: &events)

            #expect(leadFinal == .cancelled)
            #expect(askerFinal == .cancelled)
            #expect(parts.askerEnds.all == [question.elicitationId])
            #expect(parts.leadEnds.all == [question.elicitationId])
            #expect(rootEnds == [question.elicitationId])
        }
    }
}
