import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import TelemetryTestSupport
import Testing
import ULID

/// Pins the audit rules of the restore: which errors keep a claim open, which calls are
/// claimed, what the facade does with a call that completed while its child is unended, and
/// what it does when a read or a mark fails.
@Suite("The audit rules of the restore")
struct RestoreAuditTests {
    private struct MarkFailed: Error {}

    private static func child(agent: String = AgentRunTests.testWriter, token: String = "audit-token") -> RecordedChild {
        RecordedChild(
            sessionID: ULID(), agentID: agent, agentName: nil, parentSessionId: ULID(), parentToolCallId: token,
            ended: nil, firstPrompt: "audit-prompt")
    }

    // MARK: - (4) transient errors keep the claim open

    /// The error that the restore of `child` throws, or `nil` when it does not throw.
    private static func restoreError(of child: RecordedChild, on runner: AgentRunner) async -> AgentRunRestoreError? {
        do {
            _ = try await runner.restore(child)
            return nil
        } catch {
            return error
        }
    }

    @Test("a restore that fails for a reason that can pass leaves the claim of the call open")
    func transientErrorKeepsTheClaimOpen() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let (runner, claims) = RestoredRunFixture.makeRunner(harness, sessionEnding: nil)

        let error = await Self.restoreError(of: Self.child(), on: runner)

        #expect(error == .sessionEndingMissing)
        #expect(error?.isTransient == true)
        #expect(claims.all.isEmpty)
    }

    @Test("a stopped runner leaves the claim of the call open")
    func stoppedRunnerKeepsTheClaimOpen() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let (runner, claims) = RestoredRunFixture.makeRunner(harness)
        await runner.stop()

        let error = await Self.restoreError(of: Self.child(), on: runner)

        #expect(error == .stopped)
        #expect(error?.isTransient == true)
        #expect(claims.all.isEmpty)
    }

    @Test("a restore that fails for good ends the claim of the call as lost")
    func permanentErrorEndsTheClaimLost() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let (runner, claims) = RestoredRunFixture.makeRunner(harness)
        let broken = Self.child(agent: "no-such-agent")

        let error = await Self.restoreError(of: broken, on: runner)

        #expect(error?.isTransient == false)

        #expect(
            claims.all == [
                RestoredRunFixture.ClaimCall(
                    caller: broken.parentSessionId, key: broken.startCallKey, outcome: .lost)
            ])
    }

    // MARK: - (6) claims for a child with no status

    @Test("a child with no status in the journal is claimed too")
    func childWithNoStatusIsClaimed() {
        let child = Self.child()

        let claims = AgentRunRestore.claims(for: [child], statuses: [:])

        #expect(claims == [child.startCallKey])
    }

    @Test("a child whose call completed is not claimed")
    func completedCallIsNotClaimed() {
        let child = Self.child()

        let claims = AgentRunRestore.claims(for: [child], statuses: [child.startCallKey: .completed(.succeeded)])

        #expect(claims.isEmpty)
    }

    // MARK: - (7) a failed read is logged and claims nothing

    @Test("a failed read of the claims is logged, and nothing is claimed")
    func failedClaimReadIsLoggedAndClaimsNothing() async throws {
        let (claims, records) = try await TelemetryCapture.run(forbidding: []) { context in
            let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]), logger: context.logger)
            defer { try? harness.delete() }
            let runner = harness.makeRunner()
            var source = RestoreSource(directory: RouterSessionDirectory())
            source.recordedChildren = { _ in [Self.child()] }
            source.runStatuses = { _ in throw MarkFailed() }
            let claims = await runner.claims(of: ULID(), source: source)
            return (claims, context.logRecords)
        }

        #expect(claims.isEmpty)
        #expect(records.contains { "\($0.message)" == AgentsTelemetry.LogMessage.claimReadFailed })
    }

    // MARK: - (8) and (12) a completed call with an unended child

    /// A source that holds one unended child of a caller, and a status for its call.
    private static func source(
        of child: RecordedChild, status: RunStatus?, statusesFail: Bool = false
    ) -> RestoreSource {
        var source = RestoreSource(directory: RouterSessionDirectory())
        source.recordedChildren = { session in session == child.parentSessionId ? [child] : [] }
        source.runStatuses = { _ in
            if statusesFail { throw MarkFailed() }
            return status.map { [child.startCallKey: $0] } ?? [:]
        }
        source.firstPrompt = { _ in "audit-prompt" }
        return source
    }

    @Test("a child whose call completed is marked ended with that outcome and is not restored")
    func completedCallChildIsMarkedAndNotRestored() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let marks = CallRecord<String>()
        let runner = harness.makeRunner(sessionEnding: { id, reason in marks.add("\(id)-\(reason)") })
        let child = Self.child()

        let report = await runner.restoreInterrupted(
            of: child.parentSessionId, caller: nil, source: Self.source(of: child, status: .completed(.succeeded)))

        #expect(report.restored.isEmpty)
        #expect(report.failed.isEmpty)
        #expect(marks.all == ["\(child.sessionID)-\(SessionEndReason.finished)"])
    }

    @Test("a child whose mark failed is not restored by a second call, also when the journal cannot be read")
    func failedMarkIsRememberedByTheRunner() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner(sessionEnding: { _, _ in throw MarkFailed() })
        let child = Self.child()
        _ = await runner.restoreInterrupted(
            of: child.parentSessionId, caller: nil, source: Self.source(of: child, status: .completed(.failed)))

        let second = await runner.restoreInterrupted(
            of: child.parentSessionId, caller: nil, source: Self.source(of: child, status: nil, statusesFail: true))

        #expect(second.restored.isEmpty)
        #expect(second.failed.isEmpty)
    }

    @Test("a journal that cannot be read is listed as unreadable, and the restore goes on")
    func unreadableStatusesAreListed() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner(sessionEnding: { _, _ in })
        let child = Self.child()

        let report = await runner.restoreInterrupted(
            of: child.parentSessionId, caller: nil, source: Self.source(of: child, status: nil, statusesFail: true))

        #expect(report.unreadable.keys.contains(child.parentSessionId))
    }
}
