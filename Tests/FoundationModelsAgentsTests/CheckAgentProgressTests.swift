@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins the live progress that `check agent` gives for a run in operation
/// (plan.md §9.1): the answer of the task prompt and an answer to mail feed
/// the tool names and the passes while the submission holds the model, and
/// the text tail of an answer to mail updates when that answer ends.
///
/// Each run is `lead` on the `standard` slot. Its child code-reviewer is on
/// the `flash` slot.
@Suite("Check agent progress")
struct CheckAgentProgressTests {
    /// The key of the play of the lead in the task-answer test.
    private static let taskKey = "progress-task-key: list the agents"

    /// The key of the play of the lead in the mail test.
    private static let leadKey = "progress-lead-key: give the review to the reviewer"

    /// The key of the play of the child.
    private static let reviewerKey = "progress-reviewer-key: review the parser"

    /// The answer of the task answer.
    private static let answerText = "The agents are listed."

    /// The answer of the child.
    private static let reviewerText = "The parser is correct."

    /// A pass that calls `list agents` one time.
    private static let listStep = ScriptedAgentStep.toolCall(
        name: ToolVocabulary.agentsToolName, argumentsJSON: #"{"op": "list agents"}"#)

    /// The count of passes of the task answer at its gate: the tool pass
    /// before the gate counts live, at its generation call.
    private static let taskPassesAtGate = 1

    /// The count of passes of the lead at the gate of its answer to mail:
    /// the start pass and the answer of the task answer, then the tool pass
    /// of the answer to mail, which counts live.
    private static let mailPassesAtGate = 3

    /// The count of passes of the lead when it ends: the two passes of the
    /// task answer, then the tool pass and the answer of the answer to mail.
    private static let leadPassesAtEnd = 4

    /// The count of tool calls of the task answer before its gate.
    private static let taskToolCallsAtGate = 1

    /// The count of tool calls of the lead before the gate of its answer to
    /// mail: `start agent`, then `list agents`.
    private static let mailToolCallsAtGate = 2

    /// The time between two reads of the progress of a run.
    private static let pollInterval = Duration.milliseconds(10)

    /// Reads the progress of `run` until it holds `toolCount` tool names.
    /// The live record of a tool call arrives while the submission runs.
    ///
    /// - Parameters:
    ///   - run: A run whose submission is in a gate.
    ///   - toolCount: The count of tool calls before the gate.
    /// - Returns: The progress.
    /// - Throws: `CancellationError` when the test is cancelled.
    private static func progress(
        of run: AgentRun, reachingToolCount toolCount: Int
    ) async throws -> AgentRunProgress {
        while run.progress.toolNames.count < toolCount {
            try await Task.sleep(for: pollInterval)
        }
        return run.progress
    }

    @Test("check agent in the task answer gives the phase, the passes, and the tool names", .timeLimit(.minutes(1)))
    func taskTurnGivesProgress() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: Self.taskKey, steps: [Self.listStep, .wait(gate), .finalText(Self.answerText)])
            ]))
        defer { try? harness.delete() }

        let run = try await harness.makeRunner().start(NestedRunTests.lead, prompt: Self.taskKey)
        await gate.waitForArrival()
        let progress = try await Self.progress(of: run, reachingToolCount: Self.taskToolCallsAtGate)
        let report = run.report
        gate.open()
        let result = try await run.result()

        #expect(progress.phase == .taskTurn)
        #expect(progress.passes == Self.taskPassesAtGate)
        #expect(progress.toolNames == [ToolVocabulary.agentsToolName])
        #expect(report == "\(run.subject) is running.\n\(progress.text)")
        #expect(result == Self.answerText)
    }

    @Test(
        "check agent in an answer to mail gives the delivery phase and the new passes; the tail updates at its end",
        .timeLimit(.minutes(1)))
    func deliveryTurnGivesProgress() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: Self.leadKey,
                    steps: [
                        NestedRunTests.startStep(NestedRunTests.reviewer, prompt: Self.reviewerKey),
                        .finalText(NestedRunTests.startedText),
                        Self.listStep,
                        .wait(gate),
                        .finalTextOfLaterPrompts
                    ]),
                ScriptedAgentPlay(key: Self.reviewerKey, steps: [.finalText(Self.reviewerText)])
            ]))
        defer { try? harness.delete() }

        let lead = try await harness.makeRunner().start(NestedRunTests.lead, prompt: Self.leadKey)
        await gate.waitForArrival()
        let progress = try await Self.progress(of: lead, reachingToolCount: Self.mailToolCallsAtGate)
        let report = lead.report
        gate.open()
        let result = try await lead.result()

        #expect(progress.phase == .delivery)
        #expect(progress.passes == Self.mailPassesAtGate)
        #expect(
            progress.toolNames
                == Array(repeating: ToolVocabulary.agentsToolName, count: Self.mailToolCallsAtGate))
        #expect(progress.textTail == NestedRunTests.startedText)
        #expect(report == "\(lead.subject) is running.\n\(progress.text)")
        #expect(result.contains(Self.reviewerText))
        #expect(lead.progress.passes == Self.leadPassesAtEnd)
        #expect(lead.progress.textTail == String(result.suffix(AgentRunProgress.textTailLimit)))
    }
}
