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
        /// Holds the restored leaf, for a test that cancels it.
        let restoredLeafGate: ScriptedGate
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
    /// - Parameter holdRestoredLeaf: `true` when the restored leaf waits on a gate.
    /// - Returns: The cut chain.
    /// - Throws: The error of the setup.
    private static func cutChain(holdRestoredLeaf: Bool = false) async throws -> Cut {
        let leafGate = ScriptedGate()
        let restoredLeafGate = ScriptedGate()
        let layer = try TemporaryLayer.make(holding: agentFiles)
        // A restored session also matches the play of its first prompt, thus the plays of the
        // restored sessions come first.
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: leafRestoredKey,
                steps: (holdRestoredLeaf ? [.wait(restoredLeafGate)] : []) + [.finalText(leafResult)]),
            ScriptedAgentPlay(key: callerRestoredKey, steps: [.finalText("caller-resumed"), .finalTextOfLastPrompt, .finalTextOfLastPrompt, .finalTextOfLastPrompt]),
            ScriptedAgentPlay(key: middleRestoredKey, steps: [.finalText("middle-resumed"), .finalTextOfLastPrompt, .finalTextOfLastPrompt, .finalTextOfLastPrompt]),
            ScriptedAgentPlay(
                key: NestedRunTests.rootKey,
                steps: [NestedRunTests.startStep(caller, prompt: callerKey), .finalText(NestedRunTests.rootText)]),
            NestedRunTests.parentPlay(callerKey, children: [(middle, middleKey)]),
            NestedRunTests.parentPlay(middleKey, children: [(leaf, leafKey)]),
            ScriptedAgentPlay(key: leafKey, steps: [.wait(leafGate), .finalText("lost")]),
        ])
        let harness = try await AgentsToolHarness.make(script: script, registry: AgentRegistry(layers: [layer.layer]))
        let root = harness.makeRootSession(instructions: NestedRunTests.rootKey)
        _ = try await root.respond(to: NestedRunTests.rootPrompt)
        try await NestedRunTests.arrival(ofPromptContaining: leafKey, in: script)
        let callerRun = try await NestedRunTests.onlyRun(of: harness.runner, caller: root.id)
        let middleRun = try await NestedRunTests.onlyRun(of: harness.runner, caller: callerRun.id)
        let leafRun = try await NestedRunTests.onlyRun(of: harness.runner, caller: middleRun.id)
        try #require(await leafGate.waitForArrival(orEndOf: leafRun))
        let folder = try #require(root.recordingDirectory).deletingLastPathComponent()
        let directory = RouterSessionDirectory()
        await directory.useRecordingRoots { [folder] }
        return Cut(
            harness: harness, rootID: root.id, directory: directory, layer: layer, restoredLeafGate: restoredLeafGate)
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
    ///   - breaking: A child agent id for the middle child that the catalog lacks, or `nil`.
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
