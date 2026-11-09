import Foundation
import FoundationModelsExtras
@testable import FoundationModelsAgents
import Testing
import ULID

/// Pins the save of the scheduled agents with their session: a restart or a
/// resume restores them, a missed firing runs once, and the close of the
/// session removes them.
@Suite("Agent schedule store")
struct AgentScheduleStoreTests {
    /// The start time of the clock.
    private static let start = ISO8601DateFormatter().date(from: "2026-11-09T08:30:00-05:00")!

    /// The prompt whose play ends at once.
    private static let pingPrompt = "store-ping: say pong"

    /// Makes a file store whose session folders are under `root`.
    ///
    /// - Parameter root: The folder of the session folders.
    /// - Returns: The store.
    private static func store(under root: URL) -> FileAgentScheduleStore {
        FileAgentScheduleStore { session in root.appendingPathComponent(session.description, isDirectory: true) }
    }

    /// Makes a runner over the fixture agents with `clock` and `store`.
    ///
    /// - Parameters:
    ///   - harness: The run harness.
    ///   - clock: The clock.
    ///   - store: The store.
    /// - Returns: The runner.
    private static func runner(
        _ harness: AgentRunHarness, clock: ManualScheduleClock, store: FileAgentScheduleStore
    ) async -> AgentRunner {
        let runner = AgentRunner(
            registry: harness.registry,
            environment: harness.environment(
                maxRetainedRuns: AgentEnvironment.defaultMaxRetainedRuns, callerMail: { _, _, _ in MailID() }),
            scheduleClock: clock)
        await runner.useScheduleStore(store)
        return runner
    }

    /// Makes a run harness whose `code-reviewer` play ends at once.
    ///
    /// - Returns: The harness.
    private static func harness() async throws -> AgentRunHarness {
        try await AgentRunHarness.make(
            script: ScriptedAgentScript([ScriptedAgentPlay(key: pingPrompt, steps: [.finalText("pong")])]))
    }

    @Test("the file store saves and reads the tasks of a session, and an empty save removes the file")
    func fileStoreRoundTrip() async throws {
        let root = try TemporaryLayer.makeEmpty()
        defer { try? root.delete() }
        let store = Self.store(under: root.root)
        let owner = ULID()
        let task = AgentScheduledTask(
            AgentScheduleRequest(prompt: "p", spec: .interval(seconds: 600), owner: owner), now: Self.start)

        try await store.save([task], of: owner)
        let file = root.root.appendingPathComponent("\(owner)/\(FileAgentScheduleStore.fileName)")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try await store.load(of: owner) == [task])

        try await store.save([], of: owner)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try await store.load(of: owner).isEmpty)
    }

    @Test("a new runner restores the saved tasks of a session, and a missed firing runs once")
    func restoreAfterRestart() async throws {
        let root = try TemporaryLayer.makeEmpty()
        defer { try? root.delete() }
        let harness = try await Self.harness()
        defer { try? harness.delete() }
        let clock = ManualScheduleClock(start: Self.start)
        let owner = ULID()
        let first = await Self.runner(harness, clock: clock, store: Self.store(under: root.root))
        let task = await first.schedule(
            AgentScheduleRequest(
                agent: "code-reviewer", prompt: Self.pingPrompt, spec: .interval(seconds: 60), owner: owner))
        await first.stop()

        clock.advance(by: 600)
        let second = await Self.runner(harness, clock: clock, store: Self.store(under: root.root))
        let restored = try await second.restoreSchedules(of: owner)
        await second.scheduler.tick()

        #expect(restored.map(\.id) == [task.id])
        let after = try #require(await second.scheduledTask(id: task.id))
        #expect(after.runCount == 1)
        #expect(after.missedCount == 9)
        #expect(after.nextFiring == Self.start.addingTimeInterval(660))
    }

    @Test("a second restore of the same session restores nothing")
    func secondRestoreIsEmpty() async throws {
        let root = try TemporaryLayer.makeEmpty()
        defer { try? root.delete() }
        let harness = try await Self.harness()
        defer { try? harness.delete() }
        let clock = ManualScheduleClock(start: Self.start)
        let owner = ULID()
        let runner = await Self.runner(harness, clock: clock, store: Self.store(under: root.root))
        _ = await runner.schedule(AgentScheduleRequest(prompt: Self.pingPrompt, spec: .interval(seconds: 60), owner: owner))

        #expect(try await runner.restoreSchedules(of: owner).isEmpty)
    }

    @Test("closing the session removes its saved tasks")
    func closeRemovesTheFile() async throws {
        let root = try TemporaryLayer.makeEmpty()
        defer { try? root.delete() }
        let harness = try await Self.harness()
        defer { try? harness.delete() }
        let store = Self.store(under: root.root)
        let owner = ULID()
        let runner = await Self.runner(harness, clock: ManualScheduleClock(start: Self.start), store: store)
        _ = await runner.schedule(AgentScheduleRequest(prompt: Self.pingPrompt, spec: .interval(seconds: 60), owner: owner))
        #expect(try await store.load(of: owner).count == 1)

        await runner.cancelRuns(caller: owner)

        #expect(try await store.load(of: owner).isEmpty)
    }
}
