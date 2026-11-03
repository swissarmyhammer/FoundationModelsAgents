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
    /// One call of the claim completion closure.
    private struct ClaimCall: Sendable, Equatable {
        let caller: ULID
        let key: RunKey
        let outcome: OperationOutcome
    }

    /// The pieces of a restored run and what the host closures saw.
    private struct Setup {
        let harness: AgentRunHarness
        let runner: AgentRunner
        let run: AgentRun
        let child: RecordedChild
        let mails: CallRecord<String>
        let claims: CallRecord<ClaimCall>
        let marks: CallRecord<SessionEndReason>
    }

    /// The error of a mark closure that fails.
    private struct MarkFailed: Error {}

    private static let originalKey = "review-orig-key"

    /// Restores a run of a finished first life.
    ///
    /// - Parameters:
    ///   - claimResult: What the claim completion closure answers, or `nil` for no closure.
    ///   - markFails: `true` when the mark closure throws.
    ///   - gate: A gate in the restored life, or `nil`.
    ///   - deferStart: `true` to hold the start of the restored run.
    ///   - markGate: A gate that the mark closure waits on, or `nil`.
    ///   - maxDepth: The depth limit of the runner.
    private static func restored(
        claimResult: Bool?, markFails: Bool = false, gate: ScriptedGate? = nil, deferStart: Bool = false,
        markGate: ScriptedGate? = nil, maxDepth: Int = AgentEnvironment.defaultMaxDepth
    ) async throws -> Setup {
        let gateSteps: [ScriptedAgentStep] = gate.map { [.wait($0)] } ?? []
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: originalKey,
                    steps: [.finalText("first")] + gateSteps + [.finalText("restored text"), .finalTextOfLastPrompt])
            ]))
        let original = try await harness.makeRunner().start(AgentRunTests.testWriter, prompt: originalKey)
        _ = try await original.result()
        let mails = CallRecord<String>()
        let claims = CallRecord<ClaimCall>()
        let marks = CallRecord<SessionEndReason>()
        var environment = harness.environment(
            maxRetainedRuns: AgentEnvironment.defaultMaxRetainedRuns, maxDepth: maxDepth,
            callerMail: { message, _, _ in mails.add(message); return MailID() },
            sessionEnding: { _, reason in
                if let markGate { try? await markGate.wait() }
                if markFails { throw MarkFailed() }
                marks.add(reason)
            })
        if let claimResult {
            environment = environment.withClaimCompletion { caller, key, outcome, _ in
                claims.add(ClaimCall(caller: caller, key: key, outcome: outcome))
                return claimResult
            }
        }
        let runner = AgentRunner(registry: harness.registry, environment: environment)
        let child = RecordedChild(
            sessionID: original.id, agentID: AgentRunTests.testWriter, agentName: nil, parentSessionId: ULID(),
            parentToolCallId: "review-token", ended: nil, firstPrompt: originalKey)
        let run = try await runner.restore(child, deferStart: deferStart)
        return Setup(harness: harness, runner: runner, run: run, child: child, mails: mails, claims: claims, marks: marks)
    }

    @Test("a restored run whose claim completed mails a short wake-up, not the result a second time")
    func claimedResultMailsWakeUpOnly() async throws {
        let setup = try await Self.restored(claimResult: true)
        defer { try? setup.harness.delete() }

        _ = try await setup.run.result()

        #expect(setup.mails.all == [AgentsToolText.claimedResultWake])
        #expect(setup.claims.all == [
            ClaimCall(caller: setup.child.parentSessionId, key: setup.child.startCallKey, outcome: .succeeded)
        ])
    }

    @Test("a restored run whose claim did not complete mails the full result")
    func unclaimedResultMailsReport() async throws {
        let setup = try await Self.restored(claimResult: false)
        defer { try? setup.harness.delete() }

        _ = try await setup.run.result()

        #expect(setup.mails.all.count == 1)
        #expect(setup.mails.all.first?.contains("restored text") == true)
    }

    @Test("a child that cannot be restored ends its claim as lost on a caller that is not a run")
    func unrestorableChildEndsClaimLostOnHostCaller() async throws {
        let setup = try await Self.restored(claimResult: true)
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
        let runner = harness.makeRunner(sessionEnding: { _, _ in throw MarkFailed() })
        let run = try await runner.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)

        #expect(try await run.result() == AgentRunTests.finalText)
    }

    @Test("a run that finished before the stop of the runner is marked and mailed")
    func finishBeforeStopIsMarkedAndMailed() async throws {
        let markGate = ScriptedGate()
        let setup = try await Self.restored(claimResult: nil, markGate: markGate)
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
        let setup = try await Self.restored(claimResult: nil, deferStart: true)
        defer { try? setup.harness.delete() }

        setup.run.cancel()
        let final = await setup.run.finalState()

        #expect(final == .cancelled)
        #expect(setup.marks.all == [.cancelled])
        #expect(setup.mails.all.count == 1)
    }

    @Test("a stop of the runner ends a held run with no mark and no mail")
    func stopEndsHeldRunQuietly() async throws {
        let setup = try await Self.restored(claimResult: nil, deferStart: true)
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
        let setup = try await Self.restored(claimResult: nil, deferStart: true)
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
        let setup = try await Self.restored(claimResult: nil, deferStart: true, maxDepth: 2)
        defer { try? setup.harness.delete() }
        let grandchild = RecordedChild(
            sessionID: ULID(), agentID: AgentRunTests.testWriter, agentName: nil, parentSessionId: setup.run.id,
            parentToolCallId: "grand", ended: nil)

        await #expect(throws: AgentRunRestoreError.tooDeep(depth: 3, maxDepth: 2)) {
            try await setup.runner.restore(grandchild, caller: setup.run)
        }
    }
}
