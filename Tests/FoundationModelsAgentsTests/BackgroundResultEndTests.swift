@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

/// Pins the end of a run on the no-work of its session: a background tool
/// result that settles while the answer of the task prompt still runs comes
/// to the model, and the answer to it is the result of the run.
///
/// Seen live in the bench run planner24 (django__django-13447): a coder run
/// ended with its status text "waiting on …" as its report, because the
/// idle rule of the run skipped the result mail that waited in the queue,
/// and the close of the session cancelled the answer that carried it.
///
/// The order of each step is fixed with gates: the tool call answers with a
/// pending envelope, the next pass of the first answer holds on a gate, the
/// test opens the gate of the tool run and waits until the run plane settled
/// the run (`runSettled`), and then lets the first answer end with its status text.
@Suite("The end of a run with a background result")
struct BackgroundResultEndTests {
    /// The name of the tool that the run calls. The fixture agent
    /// code-reviewer lists it in its `tools` key.
    private static let toolName = "Read"

    /// The output of the background run.
    private static let toolOutput = "background-result: 3 tests failed in test_admin.py"

    /// The status text of the first answer, while the run still works.
    private static let status = "Status: waiting on the background run."

    @Test("a background result that settles inside the task-prompt answer is answered, and that answer is the result")
    func backgroundResultInsideTheTaskAnswerIsAnswered() async throws {
        let toolGate = ScriptedGate()
        let answerGate = ScriptedGate()
        var tools = ToolCatalog()
        tools.register(Self.toolName) {
            GatedBackgroundTool(name: Self.toolName, output: Self.toolOutput, gate: toolGate)
        }
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([
                .toolCall(name: Self.toolName, argumentsJSON: #"{"text": "tests"}"#),
                .wait(answerGate),
                .finalText(Self.status),
                .finalTextOfLastPrompt
            ]),
            tools: tools)
        defer { try? harness.delete() }
        let request = try harness.request(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        let run = await harness.makeRun(request)

        run.begin(request, environment: harness.environment)
        try #require(await answerGate.waitForArrival(orEndOf: run))
        let session = try #require(run.heldSession)
        let envelope = try #require(harness.script.toolOutputs.first)
        let token = try #require(ScriptedTranscriptText.completionToken(in: envelope))
        var events = await session.streamSessionEvents().makeAsyncIterator()
        toolGate.open()
        try #require(await Self.waitForSettlement(of: token, in: &events))
        answerGate.open()
        let result = try await run.result()

        #expect(result != Self.status)
        #expect(result.contains(Self.toolOutput), "\(result)")
        #expect(run.state == .finished(result))
    }

    /// Reads `events` until the run plane settled the run of `token`.
    ///
    /// - Parameters:
    ///   - token: The completion token of the run.
    ///   - events: A session-event subscription made before the run settled.
    /// - Returns: `true` when the run settled, `false` when the
    ///   subscription ended first.
    private static func waitForSettlement(
        of token: String, in events: inout AsyncStream<SessionOutput>.Iterator
    ) async -> Bool {
        while let output = await events.next() {
            if case .runSettled(let terminal) = output.event, terminal.correlationID == token {
                return true
            }
        }
        return false
    }
}
