@testable import FoundationModelsAgents
import TelemetryTestSupport
import Testing

/// Rule 4 and rule 5 of the OpenTelemetry design of 2026-09-28: no span, log
/// record or metric of an agent run carries content.
///
/// A scripted parent run starts one child run. A distinctive secret word is
/// in the task text of both runs, in the answer of the child, and in the
/// argument of a tool call of the child. The suite forbids each secret word
/// in the capture of `TelemetryCapture`, which records one issue for each
/// span attribute, log record or metric dimension that holds one.
///
/// The capture binds its tracer and its metrics factory to the task of the
/// test as task-local values. The harness is made inside the capture, thus
/// each task that inherits the task-local values of the test reports to the
/// capture.
@Suite("Telemetry content safety: no task text, answer or tool argument in the telemetry of a run")
struct TelemetryContentSafetyTests {
    /// The secret word of the task text of each run.
    private static let taskSecret = "task-secret-7c1d"

    /// The secret word of the answer of the child run.
    private static let answerSecret = "answer-secret-3e8b"

    /// The secret word of the argument of the tool call of the child run.
    private static let argumentSecret = "argument-secret-51fa"

    /// The strings that no place of the telemetry may carry.
    private static let forbidden = [taskSecret, answerSecret, argumentSecret]

    /// The name of the tool that the child calls. The fixture agent
    /// code-reviewer lists it in its `tools` key.
    private static let readToolName = "Read"

    /// The task text of the parent run. It is the key of its play.
    private static let leadTask = "content-safety-lead-key: divide the task \(taskSecret)"

    /// The task text of the child run. It is the key of its play.
    private static let reviewerTask = "content-safety-reviewer-key: review the parser \(taskSecret)"

    /// The answer of the child run.
    private static let reviewerAnswer = "The parser holds \(answerSecret)."

    /// The script: the lead starts code-reviewer, and code-reviewer calls
    /// the Read tool with the secret argument, then answers.
    private static var script: ScriptedAgentScript {
        ScriptedAgentScript([
            NestedRunTests.parentPlay(leadTask, children: [(NestedRunTests.reviewer, reviewerTask)]),
            ScriptedAgentPlay(
                key: reviewerTask,
                steps: [
                    .toolCall(name: readToolName, argumentsJSON: #"{"text": "\#(argumentSecret)"}"#),
                    .finalText(reviewerAnswer)
                ])
        ])
    }

    /// The tool catalog of each run: the Read tool that the child calls.
    private static var tools: ToolCatalog {
        var tools = ToolCatalog()
        tools.register(readToolName) { ProbeTool(name: readToolName) }
        return tools
    }

    @Test(
        "a parent and a child run carry no task text, no answer and no tool argument in their telemetry",
        .timeLimit(.minutes(1)))
    func parentAndChildRunsCarryNoContent() async throws {
        let context = try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let harness = try await AgentRunHarness.make(script: Self.script, tools: Self.tools)
            defer { try? harness.delete() }
            let lead = try await harness.makeRunner().start(NestedRunTests.lead, prompt: Self.leadTask)
            let result = try await lead.result()
            #expect(result.contains(Self.answerSecret))
            #expect(harness.script.toolNames(ofPlay: Self.reviewerTask)?.contains(Self.readToolName) == true)
            return context
        }

        Self.expectMeasuredRuns(in: context)
    }

    /// Expects that the capture measured the runs. A capture that recorded
    /// nothing passes the content check with no issue, thus the test states
    /// what the capture holds.
    ///
    /// The package emits no telemetry of its own yet. The capture holds the
    /// spans that the Router opens in the task of the test when the harness
    /// resolves the profile and makes a session. Each change that makes the
    /// package emit a span, a log record or a metric adds the expectation of
    /// that record here, thus the content check reads it.
    ///
    /// - Parameter context: The capture of the runs.
    private static func expectMeasuredRuns(in context: TelemetryCapture.Context) {
        #expect(!context.spans.isEmpty)
    }
}
