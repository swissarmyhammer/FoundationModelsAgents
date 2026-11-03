import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing
import ULID

/// Pins the rules of the crash and restore review: what a restored run sends to its caller,
/// when it marks its session, what a cancel of a held run does, and the order of the restore.
@Suite("The rules of the restore review")
struct RestoreReviewFixTests {
    @Test("a restored run whose claim completed mails a short wake-up, not the result a second time")
    func claimedResultMailsWakeUpOnly() async throws {
        let setup = try await RestoredRunFixture.make(claimResult: true)
        defer { try? setup.harness.delete() }

        _ = try await setup.run.result()

        #expect(setup.mails.all == [AgentsToolText.claimedResultWake])
        #expect(setup.claims.all == [
            RestoredRunFixture.ClaimCall(caller: setup.child.parentSessionId, key: setup.child.startCallKey, outcome: .succeeded)
        ])
    }

    @Test("a restored run whose claim did not complete mails the full result")
    func unclaimedResultMailsReport() async throws {
        let setup = try await RestoredRunFixture.make(claimResult: false)
        defer { try? setup.harness.delete() }

        _ = try await setup.run.result()

        #expect(setup.mails.all.count == 1)
        #expect(setup.mails.all.first?.contains("restored text") == true)
    }

    @Test("a child that cannot be restored ends its claim as lost on a caller that is not a run")
    func unrestorableChildEndsClaimLostOnHostCaller() async throws {
        let setup = try await RestoredRunFixture.make(claimResult: true)
        defer { try? setup.harness.delete() }
        let broken = RecordedChild(
            sessionID: ULID(), agentID: "no-such-agent", agentName: nil, parentSessionId: ULID(),
            parentToolCallId: "broken-token", ended: nil)

        _ = try? await setup.runner.restore(broken)

        #expect(setup.claims.all.last?.outcome == .lost)
        #expect(setup.claims.all.last?.key == broken.startCallKey)
    }

    @Test("a failed mark of a live run does not withhold its result")
    func failedMarkOfLiveRunKeepsResult() async throws {
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner(sessionEnding: { _, _ in throw RestoredRunFixture.MarkFailed() })
        let run = try await runner.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)

        #expect(try await run.result() == AgentRunTests.finalText)
    }

    @Test("a run that finished before the stop of the runner is marked and mailed")
    func finishBeforeStopIsMarkedAndMailed() async throws {
        let markGate = ScriptedGate()
        let setup = try await RestoredRunFixture.make(claimResult: nil, markGate: markGate)
        defer { try? setup.harness.delete() }
        await markGate.waitForArrival()
        let stopping = Task { await setup.runner.stop() }

        markGate.open()
        await stopping.value
        _ = await setup.run.finalState()

        #expect(setup.marks.all == [.finished])
        #expect(setup.mails.all.count == 1)
    }

    @Test("a cancel of a held run marks it cancelled, mails its caller, and ends it")
    func cancelOfHeldRunMarksAndMails() async throws {
        let setup = try await RestoredRunFixture.make(claimResult: nil, deferStart: true)
        defer { try? setup.harness.delete() }

        setup.run.cancel()
        let final = await setup.run.finalState()

        #expect(final == .cancelled)
        #expect(setup.marks.all == [.cancelled])
        #expect(setup.mails.all.count == 1)
    }

    @Test("a stop of the runner ends a held run with no mark and no mail")
    func stopEndsHeldRunQuietly() async throws {
        let setup = try await RestoredRunFixture.make(claimResult: nil, deferStart: true)
        defer { try? setup.harness.delete() }

        await setup.runner.stop()
        let final = await setup.run.finalState()

        #expect(final == .cancelled)
        #expect(setup.marks.all.isEmpty)
        #expect(setup.mails.all.isEmpty)
    }

    @Test("a runner with no mark closure refuses a restore")
    func restoreNeedsTheMarkClosure() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let child = RecordedChild(
            sessionID: ULID(), agentID: AgentRunTests.testWriter, agentName: nil, parentSessionId: ULID(),
            parentToolCallId: "t", ended: nil)

        await #expect(throws: AgentRunRestoreError.sessionEndingMissing) {
            try await harness.makeRunner(sessionEnding: nil).restore(child)
        }
    }

    @Test("a restore with a caller run that is not the caller session of the child is refused")
    func callerMismatchIsRefused() async throws {
        let setup = try await RestoredRunFixture.make(claimResult: nil, deferStart: true)
        defer { try? setup.harness.delete() }
        let other = RecordedChild(
            sessionID: ULID(), agentID: AgentRunTests.testWriter, agentName: nil, parentSessionId: ULID(),
            parentToolCallId: "other", ended: nil)

        await #expect(throws: AgentRunRestoreError.callerMismatch) {
            try await setup.runner.restore(other, caller: setup.run)
        }
    }

    @Test("a grandchild restored below a caller run has the depth of the real chain")
    func depthFollowsTheCallerChain() async throws {
        let setup = try await RestoredRunFixture.make(claimResult: nil, deferStart: true, maxDepth: 2)
        defer { try? setup.harness.delete() }
        let grandchild = RecordedChild(
            sessionID: ULID(), agentID: AgentRunTests.testWriter, agentName: nil, parentSessionId: setup.run.id,
            parentToolCallId: "grand", ended: nil)

        await #expect(throws: AgentRunRestoreError.tooDeep(depth: 3, maxDepth: 2)) {
            try await setup.runner.restore(grandchild, caller: setup.run)
        }
    }
}
