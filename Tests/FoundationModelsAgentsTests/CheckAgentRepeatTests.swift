@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing
import ULID

/// Pins the `check agent` text of a run in operation: it holds the shared
/// pending-work instruction, and a repeated check by the same caller with no
/// progress since the last check of that caller gives the short repeat text
/// alone (``AgentRun/repeatedCheckText``): stop checking, and post the status.
///
/// Seen live in the bench run planner24 (django__django-14752): the root
/// checked two running planners in alternation 60 times in one answer, and
/// each answer gave the full still-working text again.
///
/// The tests call the tool outside a Router session, thus the caller of the
/// tool is `nil`. A play matches by a key in the prompt of the run.
@Suite("Check agent repeat")
struct CheckAgentRepeatTests {
    /// The agent that each run starts.
    private static let reviewer = AgentRunTests.reviewer

    /// The prompt of each run. It is also the key of the play of the run.
    private static let prompt = "repeat-check-key: review the diff"

    /// The final text of the play of a run.
    private static let finalText = "The diff is correct."

    /// The sentence that starts a repeated check with no progress.
    private static let unchangedSentence = "You checked agent"

    /// A text delta that changes the progress of a gated run.
    private static let progressText = "Half of the diff is read."

    /// Starts one gated run of the reviewer through the tool.
    ///
    /// - Parameters:
    ///   - gate: The gate of the play of the run.
    ///   - harness: The harness of the tool.
    /// - Returns: The run when its turn is in the gate.
    private static func startGatedRun(gate: ScriptedGate, in harness: AgentsToolHarness) async throws -> AgentRun {
        _ = try await harness.call("start agent", ["name": reviewer, "prompt": prompt])
        let run = try #require(await harness.runner.runs.first)
        await gate.waitForArrival()
        return run
    }

    /// Makes a harness whose one play waits for `gate`, then finishes.
    ///
    /// - Parameter gate: The gate of the play.
    /// - Returns: The harness.
    private static func harness(gate: ScriptedGate) async throws -> AgentsToolHarness {
        try await AgentsToolHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: prompt, steps: [.wait(gate), .finalText(finalText)])
            ]))
    }

    @Test("the text of a running run holds the shared pending-work instruction")
    func runningTextHoldsPendingWorkInstruction() async throws {
        let gate = ScriptedGate()
        let harness = try await Self.harness(gate: gate)
        defer { try? harness.delete() }

        let run = try await Self.startGatedRun(gate: gate, in: harness)
        let checked = try await harness.call("check agent", ["id": run.id.description])
        gate.open()
        _ = try await run.result()

        #expect(checked.contains(PendingRunEnvelope.pendingWorkInstruction))
        #expect(checked.hasPrefix("Agent \(Self.reviewer) (\(run.id)) is still working.\n"))
    }

    @Test("a repeated check with no progress gives the short repeat text alone, also with no id")
    func repeatedCheckWithNoProgressLeadsWithUnchangedSentence() async throws {
        let gate = ScriptedGate()
        let harness = try await Self.harness(gate: gate)
        defer { try? harness.delete() }

        let run = try await Self.startGatedRun(gate: gate, in: harness)
        let first = try await harness.call("check agent", ["id": run.id.description])
        let second = try await harness.call("check agent", ["id": run.id.description])
        let third = try await harness.call("check agent")
        gate.open()
        _ = try await run.result()

        #expect(first == AgentsToolOperationsTests.gatedReport(of: run))
        #expect(second == run.repeatedCheckText)
        #expect(second.contains("Do not check it again."))
        #expect(second.contains("post your status as plain text now"))
        #expect(!second.contains(PendingRunEnvelope.pendingWorkInstruction))
        #expect(third == second)
    }

    @Test("a check after progress does not lead with the unchanged sentence")
    func checkAfterProgressDoesNotLead() async throws {
        let gate = ScriptedGate()
        let harness = try await Self.harness(gate: gate)
        defer { try? harness.delete() }

        let run = try await Self.startGatedRun(gate: gate, in: harness)
        let first = try await harness.call("check agent", ["id": run.id.description])
        run.record(.textDelta(Self.progressText))
        let second = try await harness.call("check agent", ["id": run.id.description])
        gate.open()
        _ = try await run.result()

        #expect(!second.hasPrefix(Self.unchangedSentence))
        #expect(second != first)
        #expect(second.hasSuffix("; text so far: \(Self.progressText)"))
    }

    @Test("a check by an other caller does not lead with the unchanged sentence")
    func checkByOtherCallerDoesNotLead() async throws {
        let gate = ScriptedGate()
        let harness = try await Self.harness(gate: gate)
        defer { try? harness.delete() }
        let other = ULID()

        let run = try await Self.startGatedRun(gate: gate, in: harness)
        let first = try await harness.call("check agent", ["id": run.id.description])
        let byOther = run.checkReport(by: other)
        let againByOther = run.checkReport(by: other)
        gate.open()
        _ = try await run.result()

        #expect(byOther == first)
        #expect(againByOther == run.repeatedCheckText)
    }

    @Test("a repeated check of a finished run gives the same finished text")
    func repeatedCheckOfFinishedRunIsUnchanged() async throws {
        let gate = ScriptedGate()
        let harness = try await Self.harness(gate: gate)
        defer { try? harness.delete() }

        let run = try await Self.startGatedRun(gate: gate, in: harness)
        gate.open()
        _ = try await run.result()
        let first = try await harness.call("check agent", ["id": run.id.description])
        let second = try await harness.call("check agent", ["id": run.id.description])

        #expect(first == "Agent \(Self.reviewer) (\(run.id)) finished.\n\n\(Self.finalText)")
        #expect(second == first)
    }

    @Test("checks of two running agents in alternation give the repeat text from the second check of each")
    func alternatingChecksOfTwoAgentsGiveTheRepeatText() async throws {
        let gates = [ScriptedGate(), ScriptedGate()]
        let prompts = [Self.prompt, "second-repeat-key: review the tests"]
        let harness = try await AgentsToolHarness.make(
            script: ScriptedAgentScript(
                zip(prompts, gates).map { prompt, gate in
                    ScriptedAgentPlay(key: prompt, steps: [.wait(gate), .finalText(Self.finalText)])
                }))
        defer { try? harness.delete() }

        var runs: [AgentRun] = []
        for (prompt, gate) in zip(prompts, gates) {
            _ = try await harness.call("start agent", ["name": Self.reviewer, "prompt": prompt])
            await gate.waitForArrival()
            runs = await harness.runner.runs
        }
        try #require(runs.count == 2)
        var answers: [String] = []
        for _ in 0..<3 {
            for run in runs {
                answers.append(try await harness.call("check agent", ["id": run.id.description]))
            }
        }
        gates.forEach { $0.open() }
        for run in runs {
            _ = try await run.result()
        }

        #expect(answers[0] == AgentsToolOperationsTests.gatedReport(of: runs[0]))
        #expect(answers[1] == AgentsToolOperationsTests.gatedReport(of: runs[1]))
        #expect(Array(answers[2...]) == [runs[0], runs[1], runs[0], runs[1]].map(\.repeatedCheckText))
    }
}
