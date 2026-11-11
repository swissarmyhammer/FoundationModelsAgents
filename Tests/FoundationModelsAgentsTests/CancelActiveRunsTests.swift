import FoundationModels
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing
import ULID

/// Pins the cascade of a cancel of the runs of a caller
/// (``AgentRunner/cancelActiveRuns(caller:)``): the run, the runs that it
/// started, and the background tool work of each of their sessions stop.
///
/// Seen live in the bench run oneplan24 (django__django-13964): at the time
/// limit the host cancelled the root, the coder that the root started kept a
/// full test suite running, and the host had to kill the process.
///
/// The root starts ``lead``, the lead starts ``worker``, and the worker calls
/// ``shellToolName``, a background tool whose run holds on a gate as a long
/// shell command holds.
@Suite("The cancel of the runs of a caller")
struct CancelActiveRunsTests {
    /// The agent that the root starts.
    private static let lead = "cancel-lead"

    /// The agent that the lead starts.
    private static let worker = "cancel-worker"

    /// The name of the background tool of the worker.
    private static let shellToolName = "shell"

    /// The instructions of the root session. It is also the key of its play.
    private static let rootKey = "cancel-root-key"

    /// The key of the play of the lead.
    private static let leadKey = "cancel-lead-key: give the tests to the worker"

    /// The key of the play of the worker.
    private static let workerKey = "cancel-worker-key: run the full test suite"

    /// The agent files of the temporary layer, by path.
    private static let agentFiles = [
        AgentDocumentPath.of(lead): """
            ---
            name: \(lead)
            description: Gives the tests to the worker.
            tools: Agent(\(worker))
            ---

            You are a lead.
            """,
        AgentDocumentPath.of(worker): """
            ---
            name: \(worker)
            description: Runs the tests.
            tools: \(shellToolName)
            ---

            You run the tests.
            """,
    ]

    /// The play of a session that starts `name` with `prompt`, then answers
    /// each mail with the text of its last prompt.
    ///
    /// - Parameters:
    ///   - key: The key of the play.
    ///   - name: The agent to start.
    ///   - prompt: The prompt of that run.
    /// - Returns: The play.
    private static func startingPlay(_ key: String, starting name: String, prompt: String) -> ScriptedAgentPlay {
        ScriptedAgentPlay(
            key: key,
            steps: [NestedRunTests.startStep(name, prompt: prompt), .finalText("I started an agent.")]
                + [ScriptedAgentStep](repeating: .finalTextOfLastPrompt, count: 3))
    }

    @Test("a cancel of the root's runs cancels its run, the run that it started, and the shell work of that run")
    func cancelCascades() async throws {
        let gate = ScriptedGate()
        let record = CancelRecordingBackgroundTool.Record()
        var tools = ToolCatalog()
        tools.register(Self.shellToolName) {
            CancelRecordingBackgroundTool(name: Self.shellToolName, gate: gate, record: record)
        }
        let plays = [
            Self.startingPlay(Self.rootKey, starting: Self.lead, prompt: Self.leadKey),
            Self.startingPlay(Self.leadKey, starting: Self.worker, prompt: Self.workerKey),
            ScriptedAgentPlay(
                key: Self.workerKey,
                steps: [.toolCall(name: Self.shellToolName, argumentsJSON: #"{"text": "tests"}"#), .finalText("ran")]
                    + [ScriptedAgentStep](repeating: .finalTextOfLastPrompt, count: 2))
        ]
        try await AgentRunHarness.withLayer(holding: Self.agentFiles, plays: plays, tools: tools) { harness in
            let runner = harness.makeRunner()
            let agentsTool = try await AgentsTool.make(context: AgentsToolContext(runner: runner))
            let root = AgentRunHarness.makeRootSession(
                on: harness.profile.standard, instructions: Self.rootKey, tools: [agentsTool])
            try root.send("Run the tests.")
            let idle = Task { await root.awaitIdle() }
            defer { idle.cancel() }
            try #require(await gate.waitForArrival(orEndOf: idle))
            let leadRun = try await NestedRunTests.onlyRun(of: runner, caller: root.id)
            let workerRun = try await NestedRunTests.onlyRun(of: runner, caller: leadRun.id)

            await runner.cancelActiveRuns(caller: root.id)

            #expect(leadRun.state == .cancelled)
            #expect(workerRun.state == .cancelled)
            #expect(record.cancels == 1)
            await root.close()
        }
    }
}
