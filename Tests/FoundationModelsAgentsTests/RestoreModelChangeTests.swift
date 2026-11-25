import Foundation
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing
import ULID

/// Pins the restore of a recorded child whose slot holds another model now:
/// the run restores onto the resident model, replays its history, and
/// reports the model change.
@Suite("The restore of a recorded child onto another resident model")
struct RestoreModelChangeTests {
    /// The model that the slot of the restoring profile holds.
    private static let residentModel: ModelRef = "scripted/resident"

    /// The prompt of the first life. It is also the key of the play.
    private static let firstPrompt = "model-change-first-prompt"

    /// The final text of the restored life.
    private static let restoredText = "I went on with the new model."

    /// The restored run of a child that was recorded on
    /// ``ScriptedProfile/standardModel``, made by a runner whose `standard`
    /// slot holds ``residentModel``.
    private struct Restored {
        let harness: AgentRunHarness
        let original: AgentRun
        let run: AgentRun
    }

    /// Records a child on the first model, then restores it with a profile
    /// whose `standard` slot holds ``residentModel``.
    private static func restoreOnResidentModel() async throws -> Restored {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: firstPrompt, steps: [.finalText("first"), .finalText(restoredText)])
            ]))
        let original = try await harness.makeRunner().start(AgentRunTests.testWriter, prompt: firstPrompt)
        _ = try await original.result()
        let resident = try await harness.withStandardModel(residentModel)
        let runner = AgentRunner(
            registry: resident.registry,
            environment: resident.environment.withRecordingRoot(harness.sessionsDirectory))
        let child = RecordedChild(
            sessionID: original.id, agentID: AgentRunTests.testWriter, agentName: nil, parentSessionId: ULID(),
            parentToolCallId: "model-change-token", ended: nil, firstPrompt: firstPrompt)
        let run = try await runner.restore(child)
        return Restored(harness: resident, original: original, run: run)
    }

    @Test("a child recorded on another model restores and replays its history")
    func restoresAndReplays() async throws {
        let restored = try await Self.restoreOnResidentModel()
        defer { try? restored.harness.delete() }

        #expect(restored.run.id == restored.original.id)
        #expect(try await restored.run.result() == Self.restoredText)
    }

    @Test("a child recorded on another model reports one model change")
    func reportsOneModelChange() async throws {
        let restored = try await Self.restoreOnResidentModel()
        defer { try? restored.harness.delete() }
        _ = try await restored.run.result()

        #expect(
            restored.run.modelChanges == [
                RestoredSession.ModelChange(
                    session: restored.original.id, recordedSlot: .standard,
                    recordedModel: ScriptedProfile.standardModel, slot: .standard, model: Self.residentModel)
            ])
    }

    @Test("a child restored on its recorded model reports no model change")
    func noChangeOnTheRecordedModel() async throws {
        let fixture = try await RestoredRunFixture.make()
        defer { try? fixture.harness.delete() }
        _ = try await fixture.run.result()

        #expect(fixture.run.modelChanges.isEmpty)
    }
}
