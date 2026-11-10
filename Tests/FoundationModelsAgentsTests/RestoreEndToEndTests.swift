import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing
import ULID

/// The whole cold-resume path with the real Router and a scripted model: a
/// chain of three runs is cut in the middle, a second runner finds the
/// children on disk, restores them, and they finish.
@Suite("The restore of an interrupted chain, end to end")
struct RestoreEndToEndTests {
    private static let caller = "e2e-caller"
    private static let middle = "e2e-middle"
    private static let leaf = "e2e-leaf"

    private static let callerKey = "e2e-caller-key: start the middle"
    private static let middleKey = "e2e-middle-key: start the leaf"
    private static let leafKey = "e2e-leaf-key: do the work"
    private static let callerRestoredKey = "e2e-caller-restored-key"
    private static let middleRestoredKey = "e2e-middle-restored-key"
    private static let leafRestoredKey = "e2e-leaf-restored-key"

    /// The final text of the restored leaf.
    private static let leafResult = "e2e-leaf-result-text"

    private static let agentFiles = [
        AgentDocumentPath.of(caller): """
            ---
            name: \(caller)
            description: Starts the middle agent.
            tools: Agent
            ---

            $ARGUMENTS
            """,
        AgentDocumentPath.of(middle): """
            ---
            name: \(middle)
            description: Starts the leaf agent.
            tools: Agent
            ---

            $ARGUMENTS
            """,
        AgentDocumentPath.of(leaf): """
            ---
            name: \(leaf)
            description: Does the work.
            ---

            $ARGUMENTS
            """,
    ]

    /// A chain that was cut: the harness whose sessions the test never closed.
    private struct Cut {
        let harness: AgentsToolHarness
        let rootID: ULID
        let directory: RouterSessionDirectory
        let layer: TemporaryLayer
        /// Holds the leaf of the first life, and the restored leaf of a continuing chain, which
        /// takes the same step. A test opens it to let the leaf finish.
        let leafGate: ScriptedGate
        /// Holds the restored leaf, for a test that cancels it.
        let restoredLeafGate: ScriptedGate
        /// The folder of the recording of the middle session.
        let middleFolder: URL?
        /// The session id of the middle run.
        let middleID: ULID
        /// The session id of the leaf run.
        let leafID: ULID
        /// The path of the middle agent file in the layer.
        let layerAgentFile: String
    }

    /// The restored runs of the chain.
    private struct Restored {
        let caller: AgentRun
        let middle: AgentRun
        let leaf: AgentRun
    }

    /// Runs the chain until the leaf waits on its gate. The test does not close the
    /// sessions and does not stop the runner, as a crash leaves them: the journals hold
    /// the runs as orphans.
    ///
    /// - Parameters:
    ///   - holdRestoredLeaf: `true` when the restored leaf waits on a gate.
    ///   - continuing: `true` for plays that go on in the second life with the recorded first
    ///     prompt, as `restoreInterrupted` restores it.
    ///   - orderlyQuit: `true` to suspend every session, stop the runner, and close the root
    ///     session, as the host does on a normal quit.
    /// - Returns: The cut chain.
    /// - Throws: The error of the setup.
    private static func cutChain(
        holdRestoredLeaf: Bool = false, orderlyQuit: Bool = false, continuing: Bool = false
    ) async throws -> Cut {
        let leafGate = ScriptedGate()
        let restoredLeafGate = ScriptedGate()
        let layer = try TemporaryLayer.make(holding: agentFiles)
        // A restored session also matches the play of its first prompt, thus the plays of the
        // restored sessions come first.
        let spare: [ScriptedAgentStep] = continuing ? [.finalTextOfLastPrompt, .finalTextOfLastPrompt, .finalTextOfLastPrompt] : []
        let rootPlay = ScriptedAgentPlay(
            key: NestedRunTests.rootKey,
            steps: [NestedRunTests.startStep(caller, prompt: callerKey), .finalText(NestedRunTests.rootText)])
        let callerPlay = ScriptedAgentPlay(
            key: callerKey, steps: NestedRunTests.parentPlay(callerKey, children: [(middle, middleKey)]).steps + spare)
        let middlePlay = ScriptedAgentPlay(
            key: middleKey, steps: NestedRunTests.parentPlay(middleKey, children: [(leaf, leafKey)]).steps + spare)
        let leafPlay = ScriptedAgentPlay(
            key: leafKey, steps: [.wait(leafGate), .finalText(continuing ? leafResult : "lost")]
                + (continuing ? [.finalText(leafResult)] : []))
        let script: ScriptedAgentScript
        if continuing {
            script = ScriptedAgentScript([
                rootPlay, callerPlay, middlePlay, leafPlay,
            ])
        } else {
            // A restored session also matches the play of its first prompt, thus the plays of
            // the restored sessions come first.
            script = ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: leafRestoredKey,
                    steps: (holdRestoredLeaf ? [.wait(restoredLeafGate)] : []) + [.finalText(leafResult)]),
                ScriptedAgentPlay(
                    key: callerRestoredKey, steps: [.finalText("caller-resumed")] + Array(repeating: .finalTextOfLastPrompt, count: 3)),
                ScriptedAgentPlay(
                    key: middleRestoredKey, steps: [.finalText("middle-resumed")] + Array(repeating: .finalTextOfLastPrompt, count: 3)),
                rootPlay, callerPlay, middlePlay, leafPlay,
            ])
        }
        let harness = try await AgentsToolHarness.make(script: script, registry: AgentRegistry(layers: [layer.layer]))
        let root = harness.makeRootSession(instructions: NestedRunTests.rootKey)
        _ = try await root.respond(to: NestedRunTests.rootPrompt)
        try await NestedRunTests.arrival(ofPromptContaining: leafKey, in: script)
        let callerRun = try await NestedRunTests.onlyRun(of: harness.runner, caller: root.id)
        let middleRun = try await NestedRunTests.onlyRun(of: harness.runner, caller: callerRun.id)
        let leafRun = try await NestedRunTests.onlyRun(of: harness.runner, caller: middleRun.id)
        try #require(await leafGate.waitForArrival(orEndOf: leafRun))
        let folder = root.recordingDirectory.deletingLastPathComponent()
        if orderlyQuit {
            for session in [root, callerRun.heldSession, middleRun.heldSession, leafRun.heldSession].compactMap(\.self) {
                session.suspend()
            }
            await harness.runner.stop()
            await root.close()
        }
        let directory = RouterSessionDirectory()
        await directory.useRecordingRoots { [folder] }
        return Cut(
            harness: harness, rootID: root.id, directory: directory, layer: layer, leafGate: leafGate, restoredLeafGate: restoredLeafGate,
            middleFolder: middleRun.recordingDirectory, middleID: middleRun.id, leafID: leafRun.id, layerAgentFile: AgentDocumentPath.of(middle))
    }

    /// The unended children of `parent`, as a host selects them.
    private static func selected(under parent: ULID, in directory: RouterSessionDirectory) async throws
        -> [RecordedChild]
    {
        AgentRunRestore.select(children: try await directory.recordedChildren(of: parent))
    }

    /// The claims of the restore of the caller `parent`, for its selected children.
    private static func claims(of parent: ULID, children: [RecordedChild], in directory: RouterSessionDirectory)
        async throws -> Set<RunKey>
    {
        AgentRunRestore.claims(for: children, statuses: try await directory.runStatuses(of: parent))
    }

    /// Restores the chain with the real Router, caller first, every run deferred.
    ///
    /// - Parameters:
    ///   - cut: The cut chain.
    ///   - runner: The runner that restores the runs.
    /// - Returns: The restored runs, not started.
    private static func restoreChain(_ cut: Cut, with runner: AgentRunner) async throws -> Restored {
        let directory = cut.directory
        let first = try #require(try await selected(under: cut.rootID, in: directory).first)
        let second = try #require(try await selected(under: first.sessionID, in: directory).first)
        let third = try #require(try await selected(under: second.sessionID, in: directory).first)
        let callerClaims = try await claims(of: first.sessionID, children: [second], in: directory)
        let middleClaims = try await claims(of: second.sessionID, children: [third], in: directory)
        let callerRun = try await runner.restore(
            first, prompt: callerRestoredKey, deferStart: true, claiming: callerClaims)
        let middleRun = try await runner.restore(
            second, prompt: middleRestoredKey, deferStart: true, claiming: middleClaims)
        let leafRun = try await runner.restore(third, prompt: leafRestoredKey, deferStart: true)
        return Restored(caller: callerRun, middle: middleRun, leaf: leafRun)
    }

    /// Makes the runner of the second life, with the real directory as the mark.
    private static func secondRunner(_ cut: Cut) -> AgentRunner {
        let directory = cut.directory
        return cut.harness.runHarness.makeRunner(
            maxDepth: 4, sessionEnding: { try await directory.markEnded($0, reason: $1) })
    }

    @Test("a crash cuts the chain; the restore finishes it, completes the original calls, and marks it ended")
    func chainRestoresAndEnds() async throws {
        let cut = try await Self.cutChain()
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        let restored = try await Self.restoreChain(cut, with: Self.secondRunner(cut))
        restored.leaf.resume()
        restored.middle.resume()
        restored.caller.resume()

        let result = try await restored.caller.result()
        let callerStatuses = try await cut.directory.runStatuses(of: restored.caller.id)
        let middleStatuses = try await cut.directory.runStatuses(of: restored.middle.id)
        let leftOver = try await Self.selected(under: cut.rootID, in: cut.directory)

        #expect(result.contains(Self.leafResult))
        #expect(callerStatuses.values.contains(.completed(.succeeded)))
        #expect(middleStatuses.values.contains(.completed(.succeeded)))
        #expect(!callerStatuses.values.contains(.completed(.lost)))
        #expect(leftOver.isEmpty)
    }

    @Test("every restored run is marked ended as finished")
    func restoredRunsAreMarkedFinished() async throws {
        let cut = try await Self.cutChain()
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        let restored = try await Self.restoreChain(cut, with: Self.secondRunner(cut))
        restored.leaf.resume()
        restored.middle.resume()
        restored.caller.resume()
        _ = try await restored.caller.result()

        let reasons = try await [restored.caller, restored.middle, restored.leaf].asyncMap {
            try await cut.directory.endMarker(of: $0.id)?.reason
        }

        #expect(reasons == [.finished, .finished, .finished])
    }

    @Test("a user cancel marks the run ended, and it is not restored again")
    func userCancelIsNotRestored() async throws {
        let cut = try await Self.cutChain(holdRestoredLeaf: true)
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        let restored = try await Self.restoreChain(cut, with: Self.secondRunner(cut))
        restored.leaf.resume()
        try #require(await cut.restoredLeafGate.waitForArrival(orEndOf: restored.leaf))

        restored.leaf.cancel()
        _ = await restored.leaf.finalState()
        let marker = try await cut.directory.endMarker(of: restored.leaf.id)
        let left = try await Self.selected(under: restored.middle.id, in: cut.directory)

        #expect(marker?.reason == .cancelled)
        #expect(left.isEmpty)
    }

    @Test("a child that cannot be restored ends its claim as lost in the journal of the live caller")
    func unrestorableChildEndsClaimLost() async throws {
        let cut = try await Self.cutChain()
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        let runner = Self.secondRunner(cut)
        let directory = cut.directory
        let first = try #require(try await Self.selected(under: cut.rootID, in: directory).first)
        let second = try #require(try await Self.selected(under: first.sessionID, in: directory).first)
        let claims = try await Self.claims(of: first.sessionID, children: [second], in: directory)
        let callerRun = try await runner.restore(first, prompt: Self.callerRestoredKey, deferStart: true, claiming: claims)
        let broken = RecordedChild(
            sessionID: second.sessionID, agentID: "no-such-agent", agentName: nil,
            parentSessionId: second.parentSessionId, parentToolCallId: second.parentToolCallId, ended: nil)

        await #expect(throws: AgentRunRestoreError.unknownAgent("no-such-agent")) {
            try await runner.restore(broken, prompt: Self.middleRestoredKey, deferStart: true)
        }
        await callerRun.heldSession?.close()
        let statuses = try await directory.runStatuses(of: first.sessionID)

        #expect(statuses.values.contains(.completed(.lost)))
    }


    @Test("after an orderly quit, the runs are orphans in the journal and have no ended marker")
    func orderlyQuitLeavesOrphansUnended() async throws {
        let cut = try await Self.cutChain(orderlyQuit: true)
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        let first = try #require(try await Self.selected(under: cut.rootID, in: cut.directory).first)
        let rootStatuses = try await cut.directory.runStatuses(of: cut.rootID)

        #expect(first.ended == nil)
        #expect(rootStatuses.values.contains(.orphaned))
        #expect(!rootStatuses.values.contains(.completed(.succeeded)))
        #expect(!rootStatuses.values.contains(.completed(.cancelled)))
    }

    @Test("after an orderly quit, the restore finishes the chain and completes the original calls")
    func orderlyQuitRestoresAndCompletesCalls() async throws {
        let cut = try await Self.cutChain(orderlyQuit: true)
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        let restored = try await Self.restoreChain(cut, with: Self.secondRunner(cut))
        restored.leaf.resume()
        restored.middle.resume()
        restored.caller.resume()

        let result = try await restored.caller.result()
        let callerStatuses = try await cut.directory.runStatuses(of: restored.caller.id)
        let middleStatuses = try await cut.directory.runStatuses(of: restored.middle.id)

        #expect(result.contains(Self.leafResult))
        #expect(callerStatuses.values.contains(.completed(.succeeded)))
        #expect(middleStatuses.values.contains(.completed(.succeeded)))
    }

    @Test("cancelRuns of a caller marks its restored runs as cancelled, and they are not restored again")
    func cancelRunsMarksCancelled() async throws {
        let cut = try await Self.cutChain(holdRestoredLeaf: true)
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        let runner = Self.secondRunner(cut)
        let restored = try await Self.restoreChain(cut, with: runner)
        restored.leaf.resume()
        try #require(await cut.restoredLeafGate.waitForArrival(orEndOf: restored.leaf))

        await runner.cancelRuns(caller: restored.middle.id)
        let marker = try await cut.directory.endMarker(of: restored.leaf.id)
        let left = try await Self.selected(under: restored.middle.id, in: cut.directory)

        #expect(marker?.reason == .cancelled)
        #expect(left.isEmpty)
    }

    // MARK: - The facade

    @Test("restoreInterrupted restores a crashed chain in tree order, unstarted, and resumeAll finishes it")
    func facadeRestoresChain() async throws {
        let cut = try await Self.cutChain(continuing: true)
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        let runner = Self.secondRunner(cut)

        let report = await runner.restoreInterrupted(
            of: cut.rootID, caller: nil, directory: cut.directory)
        let callerRun = try #require(report.restored.first)
        let states = report.restored.map(\.state)
        report.resumeAll()
        cut.leafGate.open()
        let result = try await callerRun.result()

        #expect(report.restored.count == 3)
        #expect(report.restored.map(\.agent.id) == [Self.caller, Self.middle, Self.leaf])
        #expect(report.failed.isEmpty)
        #expect(states.allSatisfy { $0 == .running })
        let middleResult = try await report.restored[1].result()
        #expect(result.contains("e2e-middle"))
        #expect(middleResult.contains(Self.leafResult), "got: \(middleResult)")
    }

    @Test("a second restoreInterrupted for the same caller restores nothing")
    func facadeSecondCallRestoresNothing() async throws {
        let cut = try await Self.cutChain(continuing: true)
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        let runner = Self.secondRunner(cut)
        let first = await runner.restoreInterrupted(
            of: cut.rootID, caller: nil, directory: cut.directory)

        let second = await runner.restoreInterrupted(
            of: cut.rootID, caller: nil, directory: cut.directory)

        #expect(first.restored.count == 3)
        #expect(second.restored.isEmpty)
        #expect(second.failed.isEmpty)
    }

    @Test("a child whose agent definition is gone is failed, with its descendant, and the caller restores")
    func facadeFailsChildWithoutDefinition() async throws {
        let cut = try await Self.cutChain(continuing: true)
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        try cut.layer.remove(cut.layerAgentFile)
        try await cut.harness.runHarness.registry.reload()
        let runner = Self.secondRunner(cut)

        let report = await runner.restoreInterrupted(
            of: cut.rootID, caller: nil, directory: cut.directory)

        #expect(report.restored.map(\.agent.id) == [Self.caller])
        #expect(report.failed.map(\.isDescendantOfFailed) == [false, true])
        #expect(report.failed.last?.reason == FailedChild.ancestorReason)
    }

    @Test("a corrupt recording makes the read fail; the report says so, and the call does not throw")
    func facadeReportsUnreadableRecording() async throws {
        let cut = try await Self.cutChain(continuing: true)
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        let folder = try #require(cut.middleFolder)
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where file.lastPathComponent == "index.md" {
            try Data([0xFF, 0xFE, 0x00, 0xC3, 0x28, 0x0A]).write(to: file)
        }
        let runner = Self.secondRunner(cut)

        let report = await runner.restoreInterrupted(
            of: cut.rootID, caller: nil, directory: cut.directory)

        #expect(report.restored.isEmpty)
        #expect(report.unreadable[cut.rootID] != nil)
    }

    @Test("a status read that fails goes in the report, and the restore goes on without claims")
    func facadeReportsUnreadableStatuses() async throws {
        let cut = try await Self.cutChain(continuing: true)
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        struct StatusFailed: Error {}
        let middleID = cut.middleID
        var source = RestoreSource(directory: cut.directory)
        let realStatuses = source.runStatuses
        source.runStatuses = { session in
            if session == middleID { throw StatusFailed() }
            return try await realStatuses(session)
        }
        let runner = Self.secondRunner(cut)

        let report = await runner.restoreInterrupted(
            of: cut.rootID, caller: nil, source: source)

        #expect(report.unreadable[middleID] != nil)
        #expect(report.restored.count == 3)
    }

    @Test("a child cut in the middle of its first submission is restored with its recorded prompt")
    func facadeRestoresChildCutInItsFirstSubmission() async throws {
        let cut = try await Self.cutChain(continuing: true)
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        let runner = Self.secondRunner(cut)

        let report = await runner.restoreInterrupted(of: cut.rootID, caller: nil, directory: cut.directory)
        let leaf = try #require(report.restored.last)
        let instructions = try AgentRunTests.instructions(of: leaf)

        #expect(report.failed.isEmpty)
        #expect(leaf.agent.id == Self.leaf)
        #expect(instructions.contains(Self.leafKey))
        report.resumeAll()
        cut.leafGate.open()
        #expect(try await report.restored[0].result().contains("e2e-middle"))
    }

    @Test("a child with no recorded task prompt and no host prompt is failed, and its claim ends as lost")
    func facadeFailsChildWithoutPrompt() async throws {
        let cut = try await Self.cutChain(continuing: true)
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        // The Router records the prompt before the answer (write-ahead), so a real child always
        // has one. The source hides the prompt of the leaf, as the record of an older Router.
        let leafID = cut.leafID
        var source = RestoreSource(directory: cut.directory)
        let realChildren = source.recordedChildren
        source.recordedChildren = { session in
            try await realChildren(session).map { child in
                child.sessionID == leafID ? child.withFirstPrompt(nil) : child
            }
        }
        source.firstPrompt = { _ in nil }
        let runner = Self.secondRunner(cut)

        let report = await runner.restoreInterrupted(of: cut.rootID, caller: nil, source: source)

        #expect(report.restored.map(\.agent.id) == [Self.caller, Self.middle])
        #expect(report.failed.map(\.reason) == [FailedChild.promptNotRecordedReason])
        #expect(report.failed.first?.isDescendantOfFailed == false)
        let middleStatuses = try await cut.directory.runStatuses(of: cut.middleID)
        #expect(middleStatuses.values.contains(.completed(.lost)))
    }

    @Test("resumeAll starts the children before their callers")
    func resumeOrderIsLeavesUp() async throws {
        let cut = try await Self.cutChain(continuing: true)
        defer {
            try? cut.harness.delete()
            try? cut.layer.delete()
        }
        let report = await Self.secondRunner(cut).restoreInterrupted(
            of: cut.rootID, caller: nil, directory: cut.directory)

        #expect(report.resumeOrder.map(\.agent.id) == [Self.leaf, Self.middle, Self.caller])
        report.resumeAll()
        cut.leafGate.open()
        _ = try await report.restored[0].result()
    }
}

extension Sequence {
    /// Maps each element with an async closure, in order.
    func asyncMap<Value>(_ transform: (Element) async throws -> Value) async rethrows -> [Value] {
        var values: [Value] = []
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }
}
