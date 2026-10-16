import Foundation
import FoundationModels
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Synchronization
import Testing

@testable import agents_demo

/// Pins what happens to a question of a run whose session is headless
/// (elicitation task 33).
///
/// A host-started run is headless, and a child of a headless session is
/// headless too: a question ends at once with a cancel that gives
/// `RunPlane.noUserPresentReason`, and the run goes on. A question event
/// that still comes gets the same cancel from the guard of the run, also in
/// a run with a headless question target. The root session of `agents-demo`
/// is headless too. ``RelayedQuestionTests`` pins
/// the questions of a run under an interactive session.
///
/// A headless question ends at once, and the guard answers in the loop of
/// the run before the run reads the next event. Thus the tests need no gate
/// and no timing.
@Suite("Questions of a run")
struct AgentRunQuestionTests {
    /// The name of the tool that asks.
    private static let askToolName = "ask"

    /// The agent whose tool asks.
    private static let asker = "asker"

    /// The agent that starts ``asker``.
    private static let lead = "question-lead"

    /// The key of the play of the asker.
    private static let askerKey = "question-asker-key: ask the user"

    /// The key of the play of the lead.
    private static let leadKey = "question-lead-key: give the task to the asker"

    /// The final text of the asker.
    private static let askerText = "The asker is done."

    /// The answer of the lead to its task prompt.
    private static let leadText = "I started the asker."

    /// The answer of the asker to the mail of the answer of its question.
    private static let afterAnswerText = "I read the answer."

    /// The answer that each question of a run gets.
    private static let noUserCancel = ElicitationResponse.cancel(reason: RunPlane.noUserPresentReason)

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

    /// The name of the tool of the headless root that keeps its question
    /// target.
    private static let keepTargetToolName = "keep-target"

    /// The instructions of the headless root session. It is also the key of
    /// its play.
    private static let rootKey = "question-root-key: keep the question target"

    /// The first prompt of the headless root session.
    private static let rootPrompt = "Keep the question target."

    /// The answer of the headless root to its first prompt.
    private static let rootText = "I kept the question target."

    /// The step of the headless root that calls ``keepTargetToolName``.
    private static let keepTargetStep = ScriptedAgentStep.toolCall(
        name: keepTargetToolName, argumentsJSON: #"{"text": "keep"}"#)

    /// The answer that the test gives to a question after the run read it.
    private static let lateAnswer = ElicitationResponse.decline

    /// A tool that keeps the question target of its call
    /// (`SubagentQuestionTarget.current`).
    struct TargetKeepingTool: Tool {
        /// The arguments of the tool: one text.
        @Generable
        struct Arguments {
            /// A text that the tool ignores.
            let text: String
        }

        /// The name of the tool.
        let name = keepTargetToolName

        /// The description of the tool.
        let description = "A tool that keeps the question target of its call."

        /// The target of the last call.
        let kept = KeptTarget()

        /// Keeps the question target of the call.
        ///
        /// - Parameter arguments: The arguments, which the tool ignores.
        /// - Returns: A fixed output.
        func call(arguments: Arguments) async throws -> String {
            kept.keep(SubagentQuestionTarget.current)
            return "The target is kept."
        }
    }

    /// The question target that ``TargetKeepingTool`` kept.
    ///
    /// A class, because the tool and the test share it. A `Mutex` guards the
    /// target, thus the `Sendable` conformance is compiler-checked.
    final class KeptTarget: Sendable {
        /// The target, or `nil` before the call.
        private let target = Mutex<SubagentQuestionTarget?>(nil)

        /// The target, or `nil` before the call.
        var value: SubagentQuestionTarget? {
            target.withLock { $0 }
        }

        /// Keeps `target`.
        ///
        /// - Parameter target: The target of the call.
        func keep(_ target: SubagentQuestionTarget?) {
            self.target.withLock { $0 = target }
        }
    }

    /// The deliveries of the answers that a test gave, in order.
    ///
    /// A class, because the hook of the run and the test share it. A `Mutex`
    /// guards the deliveries, thus the `Sendable` conformance is
    /// compiler-checked.
    private final class DeliveryRecord: Sendable {
        /// The deliveries, in order.
        private let deliveries = Mutex<[ElicitationAnswerDelivery]>([])

        /// The deliveries so far.
        var all: [ElicitationAnswerDelivery] {
            deliveries.withLock { $0 }
        }

        /// Adds one delivery.
        ///
        /// - Parameter delivery: The delivery.
        func append(_ delivery: ElicitationAnswerDelivery) {
            deliveries.withLock { $0.append(delivery) }
        }
    }

    /// Makes a headless root session with ``TargetKeepingTool``, gets the
    /// question target of its tool call, and runs `body` with the target.
    /// Then it closes the root, also when `body` throws.
    ///
    /// - Parameters:
    ///   - harness: The harness. Its script holds the play of ``rootKey``.
    ///   - body: The test.
    /// - Throws: The error of the root, of `#require` when the call gave no
    ///   target, or of `body`.
    private static func withHeadlessTarget(
        in harness: AgentRunHarness, _ body: (SubagentQuestionTarget) async throws -> Void
    ) async throws {
        let tool = TargetKeepingTool()
        let root = AgentRunHarness.makeRootSession(on: harness.profile.standard, instructions: rootKey, tools: [tool])
        do {
            _ = try await root.awaitAnswer(of: root.send(rootPrompt))
            try await body(try #require(tool.kept.value))
        } catch {
            await root.close()
            throw error
        }
        await root.close()
    }

    /// The parts of one test: the harness, the answers of the tool, and the
    /// count of the question events that the observer got.
    private struct Parts {
        /// The harness over the temporary layer.
        let harness: AgentRunHarness

        /// The answers that the asking tool got.
        let answers: AskedAnswers

        /// The count of the question events of the runs.
        let questionEvents: QuestionEventCount
    }

    /// Makes a temporary layer with ``agentFiles`` and a harness over it with
    /// the asking tool and an observer that counts the question events, runs
    /// `body`, then deletes the folders.
    ///
    /// - Parameters:
    ///   - plays: The plays of the script.
    ///   - body: The test.
    /// - Throws: The error of the setup, or of `body`.
    private static func withParts(
        plays: [ScriptedAgentPlay], _ body: (Parts) async throws -> Void
    ) async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        for (path, text) in agentFiles {
            try layer.write(text, at: path)
        }
        let answers = AskedAnswers()
        let questionEvents = QuestionEventCount()
        var tools = ToolCatalog()
        tools.register(askToolName) {
            AskingTool(name: askToolName, answers: answers)
        }
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript(plays), registry: AgentRegistry(layers: [layer.layer]), tools: tools,
            runEventObserver: { _, output in questionEvents.observe(output) })
        defer { try? harness.delete() }
        try await body(Parts(harness: harness, answers: answers, questionEvents: questionEvents))
    }

    @Test("a child whose tool asks gets a cancel with the reason, ends normally, and the parent gets its result")
    func childQuestionGetsCancel() async throws {
        let plays = [
            ScriptedAgentPlay(
                key: Self.leadKey,
                steps: [
                    NestedRunTests.startStep(Self.asker, prompt: Self.askerKey),
                    .finalText(Self.leadText),
                    .finalTextOfLaterPrompts,
                ]),
            ScriptedAgentPlay(key: Self.askerKey, steps: [Self.askStep, .finalText(Self.askerText)]),
        ]
        try await Self.withParts(plays: plays) { parts in
            let runner = parts.harness.makeRunner()
            let leadRun = try await runner.start(Self.lead, prompt: Self.leadKey)
            let leadResult = try await leadRun.result()
            let child = try #require(await runner.runs(caller: leadRun.id).first)

            #expect(parts.answers.all == [Self.noUserCancel])
            #expect(child.state == .finished(Self.askerText))
            #expect(leadResult.contains(Self.askerText))
            #expect(parts.questionEvents.value == 0)
        }
    }

    @Test("a host-started run whose tool asks gets a cancel with the reason, and ends normally")
    func hostRunQuestionGetsCancel() async throws {
        let plays = [ScriptedAgentPlay(key: Self.askerKey, steps: [Self.askStep, .finalText(Self.askerText)])]
        try await Self.withParts(plays: plays) { parts in
            let run = try await parts.harness.makeRunner().start(Self.asker, prompt: Self.askerKey)
            let final = await run.finalState()

            #expect(parts.answers.all == [Self.noUserCancel])
            #expect(final == .finished(Self.askerText))
            #expect(parts.questionEvents.value == 0)
        }
    }

    @Test("in an interactive run session, the run answers the question itself with a cancel and the reason")
    func guardAnswersQuestion() async throws {
        let plays = [
            ScriptedAgentPlay(
                key: Self.askerKey, steps: [Self.askStep, .finalText(Self.askerText), .finalText(Self.afterAnswerText)])
        ]
        try await Self.withParts(plays: plays) { parts in
            let runner = parts.harness.makeRunner(runUserPresence: .interactive)
            let run = try await runner.start(Self.asker, prompt: Self.askerKey)
            let final = await run.finalState()

            #expect(parts.answers.all == [Self.noUserCancel])
            #expect(parts.questionEvents.value == 1)
            if case .finished = final {
            } else {
                Issue.record("The run did not finish: \(final)")
            }
        }
    }

    @Test("a run with a headless question target answers a question of an interactive session itself")
    func headlessTargetGuardAnswersQuestion() async throws {
        let plays = [
            ScriptedAgentPlay(
                key: Self.askerKey, steps: [Self.askStep, .finalText(Self.askerText), .finalText(Self.afterAnswerText)]),
            ScriptedAgentPlay(key: Self.rootKey, steps: [Self.keepTargetStep, .finalText(Self.rootText)]),
        ]
        try await Self.withParts(plays: plays) { parts in
            try await Self.withHeadlessTarget(in: parts.harness) { target in
                let environment = parts.harness.environment(
                    maxRetainedRuns: AgentEnvironment.defaultMaxRetainedRuns, runUserPresence: .interactive)
                var request = try parts.harness.request(Self.asker, prompt: Self.askerKey)
                let run = await AgentRun.make(
                    request, environment: environment, renderer: AgentBodyRenderer(registry: parts.harness.registry))
                let lateDeliveries = DeliveryRecord()
                run.install(
                    AgentRunIdleHooks(afterQuestion: { operation, session in
                        guard let question = operation.elicitation else { return }
                        lateDeliveries.append(
                            await session.respond(
                                elicitationId: question.elicitationId.ulidString, response: Self.lateAnswer))
                    }))
                request.questionTarget = target
                run.begin(request, environment: environment)
                let final = await run.finalState()

                #expect(target.userPresence == .headless)
                #expect(parts.answers.all == [Self.noUserCancel])
                #expect(lateDeliveries.all == [.noPendingElicitation])
                if case .finished = final {
                } else {
                    Issue.record("The run did not finish: \(final)")
                }
            }
        }
    }

    @Test("the root session of agents-demo is headless")
    func demoRootIsHeadless() {
        let configuration = AgentsDemoModes.rootConfiguration(
            instructions: AgentsDemoModes.chatInstructions, workingDirectory: FileManager.default.temporaryDirectory,
            tools: [], inlineSettleGrace: 0)

        #expect(configuration.userPresence == .headless)
    }
}
