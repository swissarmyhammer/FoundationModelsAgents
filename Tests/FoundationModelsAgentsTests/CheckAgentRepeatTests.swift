@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing
import ULID

/// Pins the `check agent` text of a run in operation: it holds the shared
/// pending-work instruction, and a repeated check by the same caller with no
/// progress since the last check of that caller leads with the unchanged
/// sentence.
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

    /// The sentence that leads a repeated check with no progress.
    private static let unchangedSentence = "You checked this agent before, and nothing changed."

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

    @Test("a repeated check with no progress leads with the unchanged sentence, also with no id")
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
        #expect(second == "\(Self.unchangedSentence) \(first)")
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
        #expect(againByOther == "\(Self.unchangedSentence) \(first)")
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
}
