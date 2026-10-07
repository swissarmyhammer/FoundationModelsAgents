@testable import FoundationModelsAgents
import FoundationModelsExtras
import InMemoryTracing
import TelemetryTestSupport
import Testing
import Tracing

/// Pins the span of each agent run (item A of the OpenTelemetry design of
/// 2026-09-28): one `FoundationModelsAgents.run` span for each run, with ids,
/// names, the depth and the outcome and no content; a child run span under
/// the `start agent` tool span of its parent; and the submission spans of the
/// session of a run under the span of that run. Each run also writes one
/// "enter" log record when it starts (item 8, hang detection).
///
/// Each test runs in a `TelemetryCapture` and gives the tracer of the capture
/// to the harness. The pump of a Router session is a detached task, thus a
/// task-local tracer does not reach a submission span or a tool span. The
/// explicit tracer does.
@Suite("Agent run tracing")
struct AgentRunTracingTests {
    /// The depth attribute of a child of a host-started run.
    private static let childDepth = Int64(AgentRunner.hostDepth + 1)

    /// The depth attribute of a host-started run.
    private static let hostDepth = Int64(AgentRunner.hostDepth)

    /// The text of each failure of the failure-kind table. The kind never
    /// depends on the text.
    private static let failureText = "failure text"

    /// The script of the nested tests: the lead starts code-reviewer, and
    /// code-reviewer answers.
    private static var nestedScript: ScriptedAgentScript {
        ScriptedAgentScript([
            NestedRunTests.parentPlay(
                NestedRunTests.leadKey, children: [(NestedRunTests.reviewer, NestedRunTests.reviewerKey)]),
            ScriptedAgentPlay(key: NestedRunTests.reviewerKey, steps: [.finalText(NestedRunTests.reviewerText)])
        ])
    }

    /// The content of the nested tests: the task texts and the answers.
    private static let nestedContent = [
        NestedRunTests.leadKey, NestedRunTests.reviewerKey, NestedRunTests.reviewerText
    ]

    /// Gives the string value of one attribute of `span`.
    ///
    /// - Parameters:
    ///   - key: The key of the attribute.
    ///   - span: The span.
    /// - Returns: The string, or `nil`.
    private static func text(_ key: String, of span: FinishedInMemorySpan) -> String? {
        CapturedTrace.text(of: span, at: key)
    }

    @Test("a host run has one run span with its name, its id, its depth and its outcome", .timeLimit(.minutes(1)))
    func hostRunHasOneRunSpan() async throws {
        let (run, trace) = try await TelemetryCapture.run(
            forbidding: [AgentRunTests.prompt, AgentRunTests.finalText]
        ) { context in
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]), tracer: context.tracer)
            defer { try? harness.delete() }
            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            _ = try await run.result()
            return (run, CapturedTrace(spans: context.spans))
        }

        let span = try trace.runSpan(of: run)
        #expect(trace.runSpans.count == 1)
        #expect(span.kind == .internal)
        #expect(Self.text(AgentsTelemetry.AttributeKey.agentName, of: span) == AgentRunTests.reviewer)
        #expect(span.attributes.get(AgentsTelemetry.AttributeKey.depth) == .int64(Self.hostDepth))
        #expect(Self.text(AgentsTelemetry.AttributeKey.outcome, of: span) == AgentsTelemetry.Outcome.finished.rawValue)
        #expect(span.attributes.get(AgentsTelemetry.AttributeKey.parentRunID) == nil)
        #expect(span.attributes.get(AgentsTelemetry.AttributeKey.callerSessionID) == nil)
        #expect(span.attributes.get(AgentsTelemetry.AttributeKey.failureKind) == nil)
        #expect(span.errors.isEmpty)
    }

    @Test("a run writes one enter record when it starts, with its ids and the ids of its span", .timeLimit(.minutes(1)))
    func runWritesOneEnterRecord() async throws {
        let (run, trace, records) = try await TelemetryCapture.run(
            forbidding: [AgentRunTests.prompt, AgentRunTests.finalText]
        ) { context in
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]), tracer: context.tracer)
            defer { try? harness.delete() }
            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            _ = try await run.result()
            return (run, CapturedTrace(spans: context.spans), context.logRecords)
        }

        let span = try trace.runSpan(of: run)
        let enterRecords = records.filter { "\($0.message)".hasSuffix(AgentsTelemetry.SpanName.run) }
        #expect(enterRecords.count == 1)
        let record = try #require(enterRecords.first)
        #expect(record.level == TracedCall.enterLevel)
        #expect(record.metadata[AgentsTelemetry.LogMetadataKey.runID] == .string(run.id.description))
        #expect(record.metadata[AgentsTelemetry.LogMetadataKey.agentName] == .string(AgentRunTests.reviewer))
        #expect(record.metadata[AgentsTelemetry.LogMetadataKey.depth] == .string("\(AgentRunner.hostDepth)"))
        let values = record.metadata.values.map { "\($0)" }
        #expect(values.contains(span.traceID))
        #expect(values.contains(span.spanID))
    }

    @Test("a failed run span has the failed outcome, the failure kind, and an error with the kind only")
    func failedRunSpanHasFailureKind() async throws {
        let (run, trace) = try await TelemetryCapture.run(forbidding: [AgentRunTests.prompt]) { context in
            let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]), tracer: context.tracer)
            defer { try? harness.delete() }
            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            _ = await run.finalState()
            return (run, CapturedTrace(spans: context.spans))
        }

        let span = try trace.runSpan(of: run)
        #expect(Self.text(AgentsTelemetry.AttributeKey.outcome, of: span) == AgentsTelemetry.Outcome.failed.rawValue)
        #expect(
            Self.text(AgentsTelemetry.AttributeKey.failureKind, of: span) == AgentsTelemetry.FailureKind.error.rawValue)
        #expect(span.status?.code == .error)
        let recorded = try #require(span.errors.first?.error as? AgentRunSpanFailure)
        #expect(span.errors.count == 1)
        #expect(recorded.kind == .error)
        #expect("\(recorded)" == AgentsTelemetry.FailureKind.error.rawValue)
    }

    @Test("a cancelled run span has the cancelled outcome and no error", .timeLimit(.minutes(1)))
    func cancelledRunSpanHasCancelledOutcome() async throws {
        let gate = ScriptedGate()
        let (run, trace) = try await TelemetryCapture.run(forbidding: [AgentRunTests.prompt]) { context in
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.wait(gate), .finalText(AgentRunTests.finalText)]),
                tracer: context.tracer)
            defer { try? harness.delete() }
            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            await gate.waitForArrival()
            run.cancel()
            _ = await run.finalState()
            return (run, CapturedTrace(spans: context.spans))
        }

        let span = try trace.runSpan(of: run)
        #expect(
            Self.text(AgentsTelemetry.AttributeKey.outcome, of: span) == AgentsTelemetry.Outcome.cancelled.rawValue)
        #expect(span.attributes.get(AgentsTelemetry.AttributeKey.failureKind) == nil)
        #expect(span.errors.isEmpty)
    }

    @Test("a run whose setup failed has one run span with the failed outcome")
    func setupFailureHasOneRunSpan() async throws {
        let (run, trace) = try await TelemetryCapture.run(forbidding: [AgentRunTests.prompt]) { context in
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]), tracer: context.tracer)
            defer { try? harness.delete() }
            let run = try await harness.start(
                NestedRunTests.lead, prompt: AgentRunTests.prompt,
                agentsTool: { _, _, _, _ in throw CancellationError() })
            return (run, CapturedTrace(spans: context.spans))
        }

        let span = try trace.runSpan(of: run)
        #expect(run.isSetupFailure)
        #expect(trace.runSpans.count == 1)
        #expect(Self.text(AgentsTelemetry.AttributeKey.outcome, of: span) == AgentsTelemetry.Outcome.failed.rawValue)
        #expect(
            Self.text(AgentsTelemetry.AttributeKey.failureKind, of: span)
                == AgentsTelemetry.FailureKind.setupFailed.rawValue)
    }

    @Test("a child run span is a child of the start agent tool span, under a submission of its parent run",
        .timeLimit(.minutes(1)))
    func childRunSpanIsChildOfToolSpan() async throws {
        let nested = try await Self.runNested()
        let (lead, child, trace) = (nested.lead, nested.child, nested.trace)

        let leadSpan = try trace.runSpan(of: lead)
        let childSpan = try trace.runSpan(of: child)
        let toolSpan = try #require(trace.parent(of: childSpan))
        let submission = try #require(trace.parent(of: toolSpan))
        #expect(toolSpan.operationName != AgentsTelemetry.SpanName.run)
        #expect(toolSpan.operationName != CapturedTrace.submissionSpanName)
        #expect(CapturedTrace.texts(of: toolSpan).contains(lead.id.description))
        #expect(submission.operationName == CapturedTrace.submissionSpanName)
        #expect(submission.parentSpanID == leadSpan.spanID)
        #expect(Self.text(AgentsTelemetry.AttributeKey.parentRunID, of: childSpan) == lead.id.description)
        #expect(Self.text(AgentsTelemetry.AttributeKey.callerSessionID, of: childSpan) == lead.id.description)
        #expect(childSpan.attributes.get(AgentsTelemetry.AttributeKey.depth) == .int64(Self.childDepth))
    }

    @Test("each submission span of a child session is a child of the child run span", .timeLimit(.minutes(1)))
    func childSubmissionsAreChildrenOfChildRunSpan() async throws {
        let nested = try await Self.runNested()

        let childSpan = try nested.trace.runSpan(of: nested.child)
        let submissions = nested.trace.submissionSpans(ofSession: nested.child.id)
        #expect(!submissions.isEmpty)
        #expect(submissions.allSatisfy { $0.parentSpanID == childSpan.spanID })
    }

    @Test("each failure of a run gives its failure kind", arguments: [
        (AgentRunFailure.bodyRenderFailed(failureText), AgentsTelemetry.FailureKind.setupFailed),
        (.skillRenderFailed(skill: failureText, description: failureText), .setupFailed),
        (.agentsMdUnreadable(failureText), .setupFailed),
        (.toolsFailed(failureText), .setupFailed),
        (.contextOverflow(failureText), .error),
        (.modelFailed(failureText), .error),
        (.hitMaxTurns(partial: failureText), .hitMaxTurns),
        (.mailDeliveryPaused(failureText), .stopped)
    ])
    func failureGivesItsKind(failure: AgentRunFailure, kind: AgentsTelemetry.FailureKind) {
        #expect(AgentsTelemetry.FailureKind(failure) == kind)
    }

    /// The runs of a nested test and the spans of its capture.
    private struct NestedTrace {
        /// The parent run: the lead.
        let lead: AgentRun

        /// The child run: code-reviewer.
        let child: AgentRun

        /// The spans of the capture.
        let trace: CapturedTrace
    }

    /// Runs the lead, which starts code-reviewer, in a capture, and waits for
    /// both runs to end.
    ///
    /// - Returns: The lead, the child, and the spans of the capture.
    /// - Throws: The error of the harness, of the lead, or of `#require`.
    private static func runNested() async throws -> NestedTrace {
        try await TelemetryCapture.run(forbidding: nestedContent) { context in
            let harness = try await AgentRunHarness.make(script: nestedScript, tracer: context.tracer)
            defer { try? harness.delete() }
            let runner = harness.makeRunner()
            let lead = try await runner.start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
            _ = try await lead.result()
            let child = try await NestedRunTests.onlyRun(of: runner, caller: lead.id)
            _ = await child.finalState()
            return NestedTrace(lead: lead, child: child, trace: CapturedTrace(spans: context.spans))
        }
    }
}
