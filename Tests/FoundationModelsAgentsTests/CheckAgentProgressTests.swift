@testable import FoundationModelsAgents
import FoundationModelsRouter
import Synchronization
import Testing

/// Pins the live progress that `check agent` gives for a run in operation:
/// the answer of the task prompt and an answer to mail feed the tool names
/// and the passes while the submission holds the model, and the text tail of
/// an answer to mail updates when that answer ends.
///
/// Each run is `lead` on the `standard` slot. Its child code-reviewer is on
/// the `flash` slot.
///
/// The order of each step is fixed. The run event observer counts the open
/// tool records of the lead (``ToolOpenWatch``). The run calls the observer of
/// an event only after it recorded each event before it. Thus the first
/// event of the lead after the last open tool record tells that the progress
/// holds that record. The test reads the progress after that event and after
/// the arrival of the model at its gate. The test uses no clock and no poll.
@Suite("Check agent progress")
struct CheckAgentProgressTests {
    /// Opens a gate at the first event of one agent after a count of open
    /// tool records of that agent.
    ///
    /// A class, because the observer and the test share it. A `Mutex` guards
    /// the count, thus the `Sendable` conformance is compiler-checked.
    private final class ToolOpenWatch: Sendable {
        /// The id of the agent whose events count.
        private let agentID: String

        /// The count of open tool records before the gate opens.
        private let openCount: Int

        /// The count of open tool records so far.
        private let opens = Mutex(0)

        /// Opens at the first event after ``openCount`` open tool records.
        let recorded = ScriptedGate()

        /// Makes a watch.
        ///
        /// - Parameters:
        ///   - agentID: The id of the agent whose events count.
        ///   - openCount: The count of open tool records before the gate
        ///     opens.
        init(agentID: String, openCount: Int) {
            self.agentID = agentID
            self.openCount = openCount
        }

        /// Counts one event of a run.
        ///
        /// - Parameters:
        ///   - run: The run of the event.
        ///   - output: The event.
        func observe(_ run: AgentRun, _ output: SessionOutput) {
            guard run.agent.id == agentID else { return }
            let isAfterLastOpen = opens.withLock { opens in
                guard opens < openCount else { return true }
                if case .toolInvocation(let record, _) = output.event, record.closedAt == nil {
                    opens += 1
                }
                return false
            }
            if isAfterLastOpen {
                recorded.open()
            }
        }
    }

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

    @Test("check agent in the task answer gives the phase, the passes, and the tool names")
    func taskTurnGivesProgress() async throws {
        let gate = ScriptedGate()
        let watch = ToolOpenWatch(agentID: NestedRunTests.lead, openCount: Self.taskToolCallsAtGate)
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: Self.taskKey, steps: [.listAgents, .wait(gate), .finalText(Self.answerText)])
            ]),
            runEventObserver: watch.observe)
        defer { try? harness.delete() }

        let run = try await harness.makeRunner().start(NestedRunTests.lead, prompt: Self.taskKey)
        await gate.waitForArrival()
        try await watch.recorded.wait()
        let progress = run.progress
        let report = run.report
        gate.open()
        let result = try await run.result()

        #expect(progress.phase == .taskTurn)
        #expect(progress.passes == Self.taskPassesAtGate)
        #expect(progress.toolNames == [ToolVocabulary.agentsToolName])
        #expect(report == "\(run.subject) is running.\n\(progress.text)")
        #expect(result == Self.answerText)
    }

    @Test("check agent in an answer to mail gives the mail phase and the new passes; the tail updates at its end")
    func answerToMailGivesProgress() async throws {
        let gate = ScriptedGate()
        let watch = ToolOpenWatch(agentID: NestedRunTests.lead, openCount: Self.mailToolCallsAtGate)
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: Self.leadKey,
                    steps: [
                        NestedRunTests.startStep(NestedRunTests.reviewer, prompt: Self.reviewerKey),
                        .finalText(NestedRunTests.startedText),
                        .listAgents,
                        .wait(gate),
                        .finalTextOfLaterPrompts
                    ]),
                ScriptedAgentPlay(key: Self.reviewerKey, steps: [.finalText(Self.reviewerText)])
            ]),
            runEventObserver: watch.observe)
        defer { try? harness.delete() }

        let lead = try await harness.makeRunner().start(NestedRunTests.lead, prompt: Self.leadKey)
        await gate.waitForArrival()
        try await watch.recorded.wait()
        let progress = lead.progress
        let report = lead.report
        gate.open()
        let result = try await lead.result()

        #expect(progress.phase == .answeringMail)
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
