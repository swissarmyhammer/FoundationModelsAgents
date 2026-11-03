import Foundation
@testable import FoundationModelsAgents
import FoundationModelsRouter
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
}
