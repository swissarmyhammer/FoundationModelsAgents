import Foundation
import Logging
@testable import FoundationModelsAgents
import FoundationModelsRouter
import TelemetryTestSupport
import Testing
import ULID

/// Pins when a run marks its session as ended
/// (``AgentEnvironment/sessionEnding``). A real end marks it: the run
/// finished, failed, or was cancelled by its caller. A stop of the runner at
/// the shutdown of the process does not mark it, thus the next start of the
/// host can restore the run.
@Suite("The ended mark of a run")
struct RunEndedMarkTests {
    /// One call of the host closure that marks a session as ended.
    private struct Mark: Sendable, Equatable {
        /// The session that the run marked.
        let session: ULID

        /// The reason of the mark.
        let reason: SessionEndReason
    }

    /// Makes the closure for the environment, and the record of its calls.
    ///
    /// - Returns: The record and the closure.
    private static func recording() -> (record: CallRecord<Mark>, closure: AgentEnvironment.SessionEnding) {
        let record = CallRecord<Mark>()
        return (record, { session, reason in record.add(Mark(session: session, reason: reason)) })
    }

    @Test("a run that finishes marks its session as finished before the result is given")
    func finishMarksFinished() async throws {
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]))
        defer { try? harness.delete() }
        let (record, closure) = Self.recording()
        let runner = harness.makeRunner(sessionEnding: closure)
        let run = try await runner.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)

        _ = try await run.result()

        #expect(record.all == [Mark(session: run.id, reason: .finished)])
    }

    @Test("a run that the caller cancels marks its session as cancelled")
    func callerCancelMarksCancelled() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.wait(gate), .finalText(AgentRunTests.finalText)]))
        defer { try? harness.delete() }
        let (record, closure) = Self.recording()
        let runner = harness.makeRunner(sessionEnding: closure)
        let run = try await runner.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        try #require(await gate.waitForArrival(orEndOf: run))

        run.cancel()
        _ = await run.finalState()

        #expect(record.all == [Mark(session: run.id, reason: .cancelled)])
    }

    @Test("a stop of the runner leaves the session of a working run unended")
    func stopDoesNotMark() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.wait(gate), .finalText(AgentRunTests.finalText)]))
        defer { try? harness.delete() }
        let (record, closure) = Self.recording()
        let runner = harness.makeRunner(sessionEnding: closure)
        let run = try await runner.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        try #require(await gate.waitForArrival(orEndOf: run))

        await runner.stop()

        #expect(record.all.isEmpty)
    }

    // MARK: - Order and shutdown of a restored run

    @Test("a restored run marks its session ended before it mails the result to its caller")
    func markComesBeforeCallerMail() async throws {
        let events = CallRecord<String>()
        let setup = try await RestoredRunFixture.make(
            sessionEnding: { _, _ in events.add("mark") }, callerMail: { _, _, _ in events.add("mail"); return MailID() },
            gate: nil)
        defer { try? setup.harness.delete() }

        _ = try await setup.run.result()

        #expect(events.all == ["mark", "mail"])
    }

    @Test("a restored run whose mark failed mails no result to its caller")
    func failedMarkMailsNothing() async throws {
        struct MarkFailed: Error {}
        let events = CallRecord<String>()
        let setup = try await RestoredRunFixture.make(
            sessionEnding: { _, _ in throw MarkFailed() }, callerMail: { _, _, _ in events.add("mail"); return MailID() },
            gate: nil)
        defer { try? setup.harness.delete() }

        _ = try await setup.run.result()

        #expect(events.all.isEmpty)
    }

    @Test("a mark that the Router refuses for a suspended session is not an error, and mails nothing")
    func suspendedMarkIsNotLoggedAndMailsNothing() async throws {
        let events = CallRecord<String>()
        try await TelemetryCapture.run(forbidding: []) { context in
            let setup = try await RestoredRunFixture.make(
                sessionEnding: { id, _ in throw SessionEndedMarkerError.sessionSuspended(id) },
                callerMail: { _, _, _ in events.add("mail"); return MailID() },
                gate: nil, logger: context.logger)
            defer { try? setup.harness.delete() }

            _ = try await setup.run.result()

            let failures = context.logRecords.filter {
                "\($0.message)" == AgentsTelemetry.LogMessage.sessionEndMarkFailed
            }
            #expect(failures.isEmpty)
        }
        #expect(events.all.isEmpty)
    }

    @Test("a stop of the runner makes a restored run mark nothing and mail nothing")
    func stopMarksAndMailsNothing() async throws {
        let gate = ScriptedGate()
        let events = CallRecord<String>()
        let setup = try await RestoredRunFixture.make(
            sessionEnding: { _, _ in events.add("mark") }, callerMail: { _, _, _ in events.add("mail"); return MailID() },
            gate: gate)
        defer { try? setup.harness.delete() }
        try #require(await gate.waitForArrival(orEndOf: setup.run))

        await setup.runner.stop()

        #expect(events.all.isEmpty)
    }

    @Test("the cancel of the runs of one caller, for a closed session, marks them cancelled")
    func cancelRunsOfCallerMarksCancelled() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.wait(gate), .finalText(AgentRunTests.finalText)]))
        defer { try? harness.delete() }
        let (record, closure) = Self.recording()
        let runner = harness.makeRunner(sessionEnding: closure)
        let caller = ULID()
        let run = try await runner.start(
            AgentRunRequest(
                definition: try #require(harness.registry.catalog().definition(named: AgentRunTests.reviewer)),
                prompt: AgentRunTests.prompt, context: nil, inheritedSlot: .standard, depth: 1, parent: nil,
                agentsTool: nil, restoredCaller: caller))
        try #require(await gate.waitForArrival(orEndOf: run))

        await runner.cancelRuns(caller: caller)

        #expect(record.all == [Mark(session: run.id, reason: .cancelled)])
    }
}
