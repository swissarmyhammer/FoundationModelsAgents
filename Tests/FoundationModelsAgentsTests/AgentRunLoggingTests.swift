@testable import FoundationModelsAgents
import Logging
import TelemetryTestSupport
import Testing

/// Pins the log records of each agent run (item B of the OpenTelemetry design
/// of 2026-09-28): one start record and one end record for each run, with the
/// ids, the name, the depth, the outcome and the duration of the run, and no
/// content. A failed run writes its end record at `.error`, with the failure
/// kind and the error type name.
///
/// Each test runs in a `TelemetryCapture` and gives the logger of the capture
/// to the harness through `AgentEnvironment.logger`. The pump of a Router
/// session is a detached task, thus only this explicit logger carries the
/// records of a child run to the capture. No test bootstraps the logging
/// system.
@Suite("Agent run logging")
struct AgentRunLoggingTests {
    /// The keys of the log metadata of a run.
    private typealias Key = AgentsTelemetry.LogMetadataKey

    /// The values of the outcome of a run.
    private typealias Outcome = AgentsTelemetry.Outcome

    /// The values of the failure kind of a run.
    private typealias Kind = AgentsTelemetry.FailureKind

    /// The agent of the temporary layer with `maxTurns: 1`.
    private static let limited = "limited-logging"

    /// The agent file of ``limited``.
    private static let limitedFile = """
        ---
        name: \(limited)
        description: Does a task in one turn.
        maxTurns: 1
        tools: Agent
        ---

        You work in one turn.
        """

    /// The path of ``limitedFile`` in the temporary layer.
    private static let limitedPath = "agents/\(limited).md"

    /// The key of the play of ``limited``.
    private static let limitedKey = "logging-limited-key: count the passes"

    /// The partial text of the ``limited`` run. It is content: no log record
    /// may hold it.
    private static let partialText = "partial-secret-9a2c"

    /// A pass that calls `list agents` one time.
    private static let listStep = ScriptedAgentStep.toolCall(
        name: ToolVocabulary.agentsToolName, argumentsJSON: #"{"op": "list agents"}"#)

    /// The error type name of each failure of a run.
    private static let runFailureTypeName = "AgentRunFailure"

    /// The error type name of a start before the first load.
    private static let runnerErrorTypeName = "AgentRunnerError"

    /// The content of the nested test: the task texts and the answers.
    private static let nestedContent = [
        NestedRunTests.leadKey, NestedRunTests.reviewerKey, NestedRunTests.reviewerText
    ]

    /// Gives the text of one metadata value of `record`.
    ///
    /// - Parameters:
    ///   - key: The metadata key.
    ///   - record: A log record.
    /// - Returns: The text of the value, or `nil` when the record has no such
    ///   key.
    private static func text(_ key: String, of record: TelemetryCapture.LogRecord) -> String? {
        record.metadata[key].map { "\($0)" }
    }

    /// The one end record of `run` in `log`.
    ///
    /// - Parameters:
    ///   - log: The records of the capture.
    ///   - run: The run.
    /// - Returns: The end record.
    /// - Throws: The error of `#require` when the run has no end record.
    private static func endRecord(of run: AgentRun, in log: CapturedLog) throws -> TelemetryCapture.LogRecord {
        let records = CapturedLog.records(log.endRecords, ofRun: run.id)
        #expect(records.count == 1)
        return try #require(records.first)
    }

    /// Expects that `record` holds the ids, the name and the depth of a
    /// host-started run of `agent`.
    ///
    /// - Parameters:
    ///   - record: A start or an end record.
    ///   - run: The run.
    ///   - agent: The name of the agent of the run.
    private static func expectIdentity(of record: TelemetryCapture.LogRecord, run: AgentRun, agent: String) {
        #expect(Self.text(Key.runID, of: record) == run.id.description)
        #expect(Self.text(Key.agentName, of: record) == agent)
        #expect(Self.text(Key.depth, of: record) == "\(AgentRunner.hostDepth)")
    }

    /// Expects that `record` has the duration of a run: a count of seconds
    /// that is zero or more.
    ///
    /// - Parameter record: An end record.
    private static func expectDuration(of record: TelemetryCapture.LogRecord) {
        let value = Self.text(Key.durationSeconds, of: record)
        let seconds = value.flatMap(Double.init)
        #expect(seconds.map { $0 >= 0 } == true)
    }

    @Test("a finished run writes one start record and one finished record at info", .timeLimit(.minutes(1)))
    func finishedRunWritesStartAndFinishedRecords() async throws {
        let (run, log) = try await TelemetryCapture.run(
            forbidding: [AgentRunTests.prompt, AgentRunTests.finalText]
        ) { context in
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]), logger: context.logger)
            defer { try? harness.delete() }
            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            _ = try await run.result()
            return (run, CapturedLog(records: context.logRecords))
        }

        let starts = CapturedLog.records(log.startRecords, ofRun: run.id)
        #expect(starts.count == 1)
        let start = try #require(starts.first)
        #expect(start.level == .info)
        Self.expectIdentity(of: start, run: run, agent: AgentRunTests.reviewer)
        let end = try Self.endRecord(of: run, in: log)
        #expect("\(end.message)" == AgentsTelemetry.LogMessage.runEnded(.finished))
        #expect(end.level == .info)
        Self.expectIdentity(of: end, run: run, agent: AgentRunTests.reviewer)
        #expect(Self.text(Key.outcome, of: end) == Outcome.finished.rawValue)
        #expect(Self.text(Key.failureKind, of: end) == nil)
        Self.expectDuration(of: end)
    }

    @Test("a run above maxTurns writes one failed record at error with its kind and its error type only",
        .timeLimit(.minutes(1)))
    func maxTurnsRunWritesFailedRecord() async throws {
        let (run, log) = try await TelemetryCapture.run(
            forbidding: [Self.limitedKey, Self.partialText]
        ) { context in
            let layer = try TemporaryLayer.makeEmpty()
            defer { try? layer.delete() }
            try layer.write(Self.limitedFile, at: Self.limitedPath)
            let harness = try await AgentRunHarness.make(
                script: ScriptedAgentScript([
                    ScriptedAgentPlay(key: Self.limitedKey, steps: [Self.listStep, .finalText(Self.partialText)])
                ]),
                registry: AgentRegistry(layers: [layer.layer]), logger: context.logger)
            defer { try? harness.delete() }
            let run = try await harness.makeRunner().start(Self.limited, prompt: Self.limitedKey)
            #expect(await run.finalState() == .failed(.hitMaxTurns(partial: Self.partialText)))
            return (run, CapturedLog(records: context.logRecords))
        }

        #expect(CapturedLog.records(log.startRecords, ofRun: run.id).count == 1)
        let end = try Self.endRecord(of: run, in: log)
        #expect("\(end.message)" == AgentsTelemetry.LogMessage.runEnded(.failed))
        #expect(end.level == .error)
        Self.expectIdentity(of: end, run: run, agent: Self.limited)
        #expect(Self.text(Key.outcome, of: end) == Outcome.failed.rawValue)
        #expect(Self.text(Key.failureKind, of: end) == Kind.hitMaxTurns.rawValue)
        #expect(Self.text(Key.errorType, of: end) == Self.runFailureTypeName)
        Self.expectDuration(of: end)
    }

    @Test("a cancelled run writes one start record and one cancelled record at info", .timeLimit(.minutes(1)))
    func cancelledRunWritesCancelledRecord() async throws {
        let gate = ScriptedGate()
        let (run, log) = try await TelemetryCapture.run(forbidding: [AgentRunTests.prompt]) { context in
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.wait(gate), .finalText(AgentRunTests.finalText)]),
                logger: context.logger)
            defer { try? harness.delete() }
            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            await gate.waitForArrival()
            run.cancel()
            _ = await run.finalState()
            return (run, CapturedLog(records: context.logRecords))
        }

        #expect(CapturedLog.records(log.startRecords, ofRun: run.id).count == 1)
        let end = try Self.endRecord(of: run, in: log)
        #expect("\(end.message)" == AgentsTelemetry.LogMessage.runEnded(.cancelled))
        #expect(end.level == .info)
        #expect(Self.text(Key.outcome, of: end) == Outcome.cancelled.rawValue)
        #expect(Self.text(Key.failureKind, of: end) == nil)
        Self.expectDuration(of: end)
    }

    @Test("a run whose setup failed writes one start record and one failed record with setupFailed")
    func setupFailureWritesFailedRecord() async throws {
        let (run, log) = try await TelemetryCapture.run(forbidding: [AgentRunTests.prompt]) { context in
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]), logger: context.logger)
            defer { try? harness.delete() }
            let run = try await harness.start(
                NestedRunTests.lead, prompt: AgentRunTests.prompt, agentsTool: { _, _ in throw CancellationError() })
            return (run, CapturedLog(records: context.logRecords))
        }

        #expect(run.isSetupFailure)
        #expect(CapturedLog.records(log.startRecords, ofRun: run.id).count == 1)
        let end = try Self.endRecord(of: run, in: log)
        #expect(end.level == .error)
        #expect(Self.text(Key.failureKind, of: end) == Kind.setupFailed.rawValue)
        #expect(Self.text(Key.errorType, of: end) == Self.runFailureTypeName)
    }

    @Test("a start before the first load writes one failed record with catalogNotLoaded and no start record")
    func startBeforeLoadWritesFailedRecord() async throws {
        let log = try await TelemetryCapture.run(forbidding: [AgentRunTests.prompt]) { context in
            let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]), logger: context.logger)
            defer { try? harness.delete() }
            let runner = AgentRunner(
                registry: AgentRegistry(stack: FixtureLibrary.stack()), environment: harness.environment)
            await #expect(throws: AgentRunnerError.catalogNotLoaded) {
                try await runner.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            }
            return CapturedLog(records: context.logRecords)
        }

        #expect(log.startRecords.isEmpty)
        #expect(log.endRecords.count == 1)
        let end = try #require(log.endRecords.first)
        #expect("\(end.message)" == AgentsTelemetry.LogMessage.runEnded(.failed))
        #expect(end.level == .error)
        #expect(Self.text(Key.agentName, of: end) == AgentRunTests.reviewer)
        #expect(Self.text(Key.failureKind, of: end) == Kind.catalogNotLoaded.rawValue)
        #expect(Self.text(Key.errorType, of: end) == Self.runnerErrorTypeName)
        #expect(Self.text(Key.runID, of: end) == nil)
    }

    @Test("the logger of the environment gets one enter, one start and one end record of a parent and of its child",
        .timeLimit(.minutes(1)))
    func parentAndChildWriteToTheLoggerOfTheEnvironment() async throws {
        let script = ScriptedAgentScript([
            NestedRunTests.parentPlay(
                NestedRunTests.leadKey, children: [(NestedRunTests.reviewer, NestedRunTests.reviewerKey)]),
            ScriptedAgentPlay(key: NestedRunTests.reviewerKey, steps: [.finalText(NestedRunTests.reviewerText)])
        ])
        let (runs, log) = try await TelemetryCapture.run(forbidding: Self.nestedContent) { context in
            let harness = try await AgentRunHarness.make(script: script, logger: context.logger)
            defer { try? harness.delete() }
            let runner = harness.makeRunner()
            let lead = try await runner.start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
            _ = try await lead.result()
            let child = try await NestedRunTests.onlyRun(of: runner, caller: lead.id)
            _ = await child.finalState()
            return ([lead, child], CapturedLog(records: context.logRecords))
        }

        for run in runs {
            #expect(CapturedLog.records(log.enterRecords, ofRun: run.id).count == 1)
            #expect(CapturedLog.records(log.startRecords, ofRun: run.id).count == 1)
            #expect(CapturedLog.records(log.endRecords, ofRun: run.id).count == 1)
        }
    }
}
