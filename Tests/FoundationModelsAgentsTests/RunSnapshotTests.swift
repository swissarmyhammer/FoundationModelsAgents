import Foundation
@testable import FoundationModelsAgents
import Testing
import ULID

/// Pins the state snapshot API of a run: ``AgentRun/snapshot``, ``AgentRunner/snapshots()``, and
/// the change stream ``AgentRunner/runChanges()``.
@Suite("The state snapshots of runs")
struct RunSnapshotTests {
    @Test("the snapshot of a finished host run names the agent and the working folder")
    func finishedSnapshot() async throws {
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]))
        defer { try? harness.delete() }
        let run = try await harness.makeRunner().start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        _ = try await run.result()

        let snapshot = run.snapshot

        #expect(snapshot.id == run.id)
        #expect(snapshot.agentID == AgentRunTests.reviewer)
        #expect(snapshot.agentName == AgentRunTests.reviewer)
        #expect(snapshot.agentDescription == run.agent.description)
        #expect(snapshot.depth == 1)
        #expect(snapshot.callerSession == nil)
        #expect(snapshot.status == .finished)
        #expect(snapshot.workingDirectory == harness.workingDirectory)
    }

    @Test("the snapshot of a run that waits on a gate is working")
    func workingSnapshot() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.wait(gate), .finalText(AgentRunTests.finalText)]))
        defer { try? harness.delete() }
        let run = try await harness.makeRunner().start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        try #require(await gate.waitForArrival(orEndOf: run))

        #expect(run.snapshot.status == .working)

        gate.open()
        _ = try await run.result()
    }

    @Test("the snapshot of a cancelled run is cancelled")
    func cancelledSnapshot() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.wait(gate), .finalText(AgentRunTests.finalText)]))
        defer { try? harness.delete() }
        let run = try await harness.makeRunner().start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        try #require(await gate.waitForArrival(orEndOf: run))

        run.cancel()
        _ = await run.finalState()

        #expect(run.snapshot.status == .cancelled)
    }

    @Test("snapshots() lists the live runs and the retained records")
    func snapshotsListLiveAndRetained() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: "snap-live-key", steps: [.wait(gate), .finalText("live")]),
                ScriptedAgentPlay(key: "snap-done-key", steps: [.finalText("done")]),
            ]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()
        let done = try await runner.start(AgentRunTests.testWriter, prompt: "snap-done-key")
        _ = try await done.result()
        let live = try await runner.start(AgentRunTests.testWriter, prompt: "snap-live-key")
        try #require(await gate.waitForArrival(orEndOf: live))

        let snapshots = await runner.snapshots()

        #expect(Set(snapshots.map(\.id)) == [done.id, live.id])
        #expect(snapshots.first { $0.id == live.id }?.status == .working)
        #expect(snapshots.first { $0.id == done.id }?.status == .finished)

        gate.open()
        _ = try await live.result()
    }

    @Test("a run change stream starts with the live runs, then gives each state change, and ends at stop")
    func changeStream() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.wait(gate), .finalText(AgentRunTests.finalText)]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()
        let run = try await runner.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        try #require(await gate.waitForArrival(orEndOf: run))
        let changes = await runner.runChanges()
        var iterator = changes.makeAsyncIterator()

        let first = await iterator.next()
        gate.open()
        _ = try await run.result()
        await runner.stop()
        var rest: [AgentRunSnapshot] = []
        while let next = await iterator.next() {
            rest.append(next)
        }

        #expect(first?.id == run.id)
        #expect(first?.status == .working)
        #expect(rest.last?.status == .finished)
        #expect(rest.allSatisfy { $0.id == run.id })
    }
}
