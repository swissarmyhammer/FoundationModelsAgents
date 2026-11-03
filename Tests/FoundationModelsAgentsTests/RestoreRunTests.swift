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
    static func child(
        _ session: ULID, agentID: String = AgentRunTests.reviewer, caller: ULID = caller, token: String? = nil
    ) -> RecordedChild {
        RecordedChild(
            sessionID: session, agentID: agentID, agentName: nil, parentSessionId: caller,
            parentToolCallId: token ?? "token-\(session)", ended: nil)
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

    @Test("a restored run has the old completion token of the start agent call")
    func restoredRunKeepsTheCompletionToken() async throws {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: AgentRunTests.prompt, steps: [.finalText("lost")]),
                ScriptedAgentPlay(
                    key: AgentsToolText.restoredRunContinue, steps: [.finalText(Self.restoredText)]),
            ]))
        defer { try? harness.delete() }
        let first = harness.makeRunner()
        let run = try await first.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        _ = try await run.result()
        let child = Self.child(run.id, token: "old-token-1")

        let restored = try await harness.makeRunner().restore(child, deferStart: true)

        #expect(restored.completionToken == "old-token-1")
    }

    @Test("the runner finds a restored run by the old completion token, in any letter case")
    func runnerFindsRestoredRunByToken() async throws {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: AgentRunTests.prompt, steps: [.finalText("lost")]),
            ]))
        defer { try? harness.delete() }
        let run = try await harness.makeRunner().start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        _ = try await run.result()
        let child = Self.child(run.id, token: "old-token-2")
        let runner = harness.makeRunner()
        let restored = try await runner.restore(child, deferStart: true)

        let found = await runner.run(completionToken: "OLD-TOKEN-2")

        #expect(found?.id == restored.id)
    }

    @Test("a claim of a run that is not an orphan makes the restore fail before the session restores")
    func claimOfNonOrphanFails() async throws {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: AgentRunTests.prompt, steps: [.finalText("done")]),
            ]))
        defer { try? harness.delete() }
        let run = try await harness.makeRunner().start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        _ = try await run.result()
        let key = RunKey(tool: ToolVocabulary.agentsToolName, correlationID: "no-such-run")

        do {
            _ = try await harness.makeRunner().restore(Self.child(run.id), claiming: [key])
            Issue.record("The restore must fail.")
        } catch {
            guard case .sessionRestoreFailed(let reason) = error else {
                Issue.record("Wrong error: \(error).")
                return
            }
            #expect(reason.contains("runNotClaimable"))
        }
    }

    @Test("the recorded session of a run holds the agent id of the run")
    func recordedSessionHoldsTheAgentID() async throws {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([ScriptedAgentPlay(key: AgentRunTests.prompt, steps: [.finalText("done")])]))
        defer { try? harness.delete() }
        let run = try await harness.makeRunner().start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        _ = try await run.result()

        let record = try AgentRunTests.recordedSession(of: run).record

        #expect(record.facts.agentID == AgentRunTests.reviewer)
    }

    @Test("a restored run uses the recorded first prompt as $ARGUMENTS when the host gives no prompt")
    func restoredRunUsesTheRecordedFirstPrompt() async throws {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: "fp-recorded-key", steps: [.finalText("from the recorded prompt"), .finalText("from the recorded prompt")]),
                ScriptedAgentPlay(key: "fp-original-key", steps: [.finalText("first life")]),
            ]))
        defer { try? harness.delete() }
        let original = try await harness.makeRunner().start(AgentRunTests.testWriter, prompt: "fp-original-key")
        _ = try await original.result()
        let child = RecordedChild(
            sessionID: original.id, agentID: AgentRunTests.testWriter, agentName: nil, parentSessionId: Self.caller,
            parentToolCallId: "fp-token", ended: nil, firstPrompt: "fp-recorded-key")

        let restored = try await harness.makeRunner().restore(child)

        let text = try await restored.result()
        #expect(text == "from the recorded prompt", "got: \(text)")
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

/// Pins the restore of a chain of three sessions: a caller, its child, and
/// the child of that child. A restored caller does not end before its
/// restored children are attached and have ended.
@Suite("The restore of a chain of recorded runs")
struct RestoreChainTests {
    /// The root session of the host that is the caller of the first run.
    private static let root = ULID()

    /// The final text of the restored grandchild.
    private static let grandchildText = "grandchild-result-key"

    /// The final text of the restored child before it gets the result of its
    /// own child.
    private static let childText = "child-first-answer"

    /// The final text of the restored caller before it gets the result of its
    /// child.
    private static let callerText = "caller-first-answer"

    /// Makes the recorded child of a session.
    ///
    /// - Parameters:
    ///   - session: The session id of the child.
    ///   - caller: The caller session.
    /// - Returns: The child.
    private static func child(_ session: ULID, caller: ULID) -> RecordedChild {
        RecordedChild(
            sessionID: session, agentID: AgentRunTests.testWriter, agentName: nil, parentSessionId: caller,
            parentToolCallId: "token-\(session)", ended: nil)
    }

    @Test("a restored caller waits for its restored child and its grandchild, and gives both results")
    func callerGetsBothResults() async throws {
        let gates = [ScriptedGate(), ScriptedGate(), ScriptedGate()]
        let originals = ["chain-orig-a", "chain-orig-b", "chain-orig-c"]
        let restores = ["chain-rest-a", "chain-rest-b", "chain-rest-c"]
        let originalPlays = zip(originals, gates).map { key, gate in
            ScriptedAgentPlay(key: key, steps: [.wait(gate), .finalText("lost")])
        }
        let restoredPlays = [
            ScriptedAgentPlay(key: restores[0], steps: [.finalText(Self.callerText), .finalTextOfLastPrompt]),
            ScriptedAgentPlay(key: restores[1], steps: [.finalText(Self.childText), .finalTextOfLastPrompt]),
            ScriptedAgentPlay(key: restores[2], steps: [.finalText(Self.grandchildText)]),
        ]
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript(originalPlays + restoredPlays))
        defer { try? harness.delete() }
        let first = harness.makeRunner()
        var runs: [AgentRun] = []
        for (index, key) in originals.enumerated() {
            let run = try await first.start(AgentRunTests.testWriter, prompt: key)
            try #require(await gates[index].waitForArrival(orEndOf: run))
            runs.append(run)
        }
        await first.stop()
        let second = harness.makeRunner(maxDepth: 4)

        let caller = try await second.restore(
            RestoreRunTests.child(runs[0].id, agentID: AgentRunTests.testWriter, caller: Self.root), prompt: restores[0], deferStart: true)
        let middle = try await second.restore(
            RestoreRunTests.child(runs[1].id, agentID: AgentRunTests.testWriter, caller: caller.id), prompt: restores[1], deferStart: true)
        let leaf = try await second.restore(
            RestoreRunTests.child(runs[2].id, agentID: AgentRunTests.testWriter, caller: middle.id), prompt: restores[2], deferStart: true)
        leaf.resume()
        middle.resume()
        caller.resume()

        let result = try await caller.result()
        #expect(result.contains(Self.grandchildText))
    }
}
