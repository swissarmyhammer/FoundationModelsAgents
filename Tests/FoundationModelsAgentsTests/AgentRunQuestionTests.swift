import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

@testable import agents_demo

/// Pins what happens to a question of a run whose session is headless
/// (elicitation task 33).
///
/// A host-started run is headless, and a child of a headless session is
/// headless too: a question ends at once with a cancel that gives
/// `RunPlane.noUserPresentReason`, and the run goes on. A question event
/// that still comes gets the same cancel from the guard of the run. The root
/// session of `agents-demo` is headless too. ``RelayedQuestionTests`` pins
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

    @Test("the root session of agents-demo is headless")
    func demoRootIsHeadless() {
        let configuration = AgentsDemoModes.rootConfiguration(
            instructions: AgentsDemoModes.chatInstructions, workingDirectory: FileManager.default.temporaryDirectory,
            tools: [], inlineSettleGrace: 0)

        #expect(configuration.userPresence == .headless)
    }
}
