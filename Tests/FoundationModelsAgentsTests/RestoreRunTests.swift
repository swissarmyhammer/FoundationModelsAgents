import Foundation
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing
import ULID

/// Pins ``AgentRunner/restore(_:prompt:)``: a recorded child continues as the
/// same session, and the runner refuses a child it cannot restore.
@Suite("The restore of a recorded child")
struct RestoreRunTests {
    /// The caller session of the recorded child.
    private static let caller = ULID()

    /// The final text of the restored run.
    private static let restoredText = "I went on and finished."

    /// Makes the recorded child of a session.
    ///
    /// - Parameters:
    ///   - session: The session id of the child.
    ///   - agentID: The agent id of the child.
    /// - Returns: The child.
    private static func child(_ session: ULID, agentID: String = AgentRunTests.reviewer) -> RecordedChild {
        RecordedChild(
            sessionID: session, agentID: agentID, agentName: nil, parentSessionId: caller,
            parentToolCallId: "token-1", ended: nil)
    }

    @Test("a run whose runner stopped continues as the same session in a new runner")
    func restoredRunKeepsItsSessionID() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: AgentRunTests.prompt, steps: [.wait(gate), .finalText("lost")]),
                ScriptedAgentPlay(
                    key: AgentsToolText.restoredRunContinue, steps: [.finalText(Self.restoredText)]),
            ]))
        defer { try? harness.delete() }
        let first = harness.makeRunner()
        let run = try await first.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        try #require(await gate.waitForArrival(orEndOf: run))
        await first.stop()

        let restored = try await harness.makeRunner().restore(Self.child(run.id))

        #expect(restored.id == run.id)
    }

    @Test("a restored run gives the final text of its continued work")
    func restoredRunFinishes() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: AgentRunTests.prompt, steps: [.wait(gate), .finalText("lost")]),
                ScriptedAgentPlay(
                    key: AgentsToolText.restoredRunContinue, steps: [.finalText(Self.restoredText)]),
            ]))
        defer { try? harness.delete() }
        let first = harness.makeRunner()
        let run = try await first.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        try #require(await gate.waitForArrival(orEndOf: run))
        await first.stop()

        let restored = try await harness.makeRunner().restore(Self.child(run.id))

        #expect(try await restored.result() == Self.restoredText)
    }

    @Test("a child with an agent id that the catalog lacks is refused")
    func unknownAgentIsRefused() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        await #expect(throws: AgentRunRestoreError.unknownAgent("no-such-agent")) {
            try await runner.restore(Self.child(ULID(), agentID: "no-such-agent"))
        }
    }

    @Test("a stopped runner refuses a restore")
    func stoppedRunnerRefuses() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()
        await runner.stop()

        await #expect(throws: AgentRunRestoreError.stopped) {
            try await runner.restore(Self.child(ULID()))
        }
    }

    @Test("a child deeper than the depth limit is refused")
    func tooDeepIsRefused() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner(maxDepth: 1)

        await #expect(throws: AgentRunRestoreError.tooDeep(depth: 2, maxDepth: 1)) {
            try await runner.restore(Self.child(ULID()))
        }
    }
}
