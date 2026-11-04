import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing
import ULID

/// Pins that a restored child session gets the transcript reader of the environment, as a live
/// child keeps the reader of its parent.
@Suite("The transcript reader of a restored run")
struct RestoredTranscriptReaderTests {
    private static let agent = "reader"
    private static let probeToolName = "transcript_probe"
    private static let firstPrompt = "restored-reader-key"

    /// The agent file: one agent that has the probe tool.
    private static let agentFiles = [
        AgentDocumentPath.of(agent): """
            ---
            name: \(agent)
            description: Reads the transcript of its session.
            tools: \(probeToolName)
            ---

            You read.
            """
    ]

    /// Restores a run of a finished first life. The restored life calls the probe tool one time.
    ///
    /// - Parameter reader: The reader of the environment, or `nil`.
    /// - Returns: The outcomes of the probe tool, after the restored run ended.
    private static func restoredOutcomes(reader: (any SessionTranscriptReader)?) async throws
        -> [TranscriptProbeTool.Outcome]
    {
        let outcomes = TranscriptProbeRecord()
        var tools = ToolCatalog()
        tools.register(probeToolName) { TranscriptProbeTool(name: probeToolName, record: outcomes) }
        let play = ScriptedAgentPlay(
            key: firstPrompt,
            steps: [
                .finalText("first"), .toolCall(name: probeToolName, argumentsJSON: #"{"text": "x"}"#),
                .finalText("restored text"),
            ])
        try await AgentRunHarness.withLayer(holding: agentFiles, plays: [play], tools: tools) { harness in
            let original = try await harness.makeRunner().start(agent, prompt: firstPrompt)
            _ = try await original.result()
            let environment = harness.environment.withTranscriptReader(reader)
            let runner = AgentRunner(registry: harness.registry, environment: environment)
            let child = RecordedChild(
                sessionID: original.id, agentID: agent, agentName: nil, parentSessionId: ULID(),
                parentToolCallId: "restored-reader-token", ended: nil, firstPrompt: firstPrompt)
            let run = try await runner.restore(child)
            _ = try await run.result()
        }
        return outcomes.all
    }

    @Test("a tool of a restored run reads a transcript when the environment has a reader")
    func restoredRunGetsTheReader() async throws {
        let outcomes = try await Self.restoredOutcomes(reader: EmptyTranscriptReader())

        #expect(outcomes == [.read])
    }

    @Test("a tool of a restored run gets noSource when the environment has no reader")
    func restoredRunWithoutReaderGetsNoSource() async throws {
        let outcomes = try await Self.restoredOutcomes(reader: nil)

        #expect(outcomes == [.noSource])
    }
}
