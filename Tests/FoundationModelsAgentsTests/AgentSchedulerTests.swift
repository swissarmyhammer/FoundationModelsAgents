import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Synchronization
import Testing
import ULID

/// Pins the scheduler: each firing is a child run of the owner session, its
/// result is mailed after every firing, an overlapping firing is skipped, a
/// gap runs once, and a task ends with its count, its end, or its session.
@Suite("Agent scheduler")
struct AgentSchedulerTests {
    /// The agent of the tests.
    private static let agent = "pinger"

    /// The prompt whose play ends at once.
    private static let pingPrompt = "scheduled-ping: say pong"

    /// The final text of the ping play.
    private static let pong = "pong"

    /// The prompt whose play waits for a gate.
    private static let holdPrompt = "scheduled-hold: wait"

    /// The final text of the hold play.
    private static let held = "held"

    /// The start time of the clock.
    private static let start = ISO8601DateFormatter().date(from: "2026-11-09T08:30:00-05:00")!

    /// The mail that the host route got.
    private final class Mailbox: Sendable {
        /// One mail.
        struct Mail: Sendable {
            /// The text.
            let text: String

            /// The sender.
            let sender: ULID

            /// The receiver.
            let receiver: ULID
        }

        /// The mail so far.
        private let mail = Mutex<[Mail]>([])

        /// The mail so far.
        var all: [Mail] {
            mail.withLock { $0 }
        }

        /// The host route.
        var route: AgentEnvironment.CallerMail {
            { [self] text, sender, receiver in
                mail.withLock { $0.append(Mail(text: text, sender: sender, receiver: receiver)) }
                return MailID()
            }
        }
    }

    /// The parts of one test.
    private struct Setup {
        /// The layer of the agents.
        let layer: TemporaryLayer

        /// The run harness.
        let harness: AgentRunHarness

        /// The runner.
        let runner: AgentRunner

        /// The clock.
        let clock: ManualScheduleClock

        /// The mail of the owner.
        let mailbox: Mailbox

        /// The owner session.
        let owner = ULID()

        /// Removes the folders.
        func delete() {
            try? harness.delete()
            try? layer.delete()
        }
    }

    /// Makes a runner with the agent ``agent`` and a default agent, a
    /// manual clock, and a mailbox.
    ///
    /// - Parameter gate: The gate of the hold play.
    /// - Returns: The setup.
    private static func makeSetup(gate: ScriptedGate = ScriptedGate()) async throws -> Setup {
        let layer = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: agent): AgentFolderFixture.agentText(
                name: agent, body: "Pinger. $ARGUMENTS"),
            "AGENT.md": AgentFolderFixture.agentText(name: "Main", body: "Main session. $ARGUMENTS")
        ])
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: pingPrompt, steps: [.finalText(pong)]),
                ScriptedAgentPlay(key: holdPrompt, steps: [.wait(gate), .finalText(held)])
            ]),
            registry: AgentRegistry(layers: [layer.layer]))
        let mailbox = Mailbox()
        let clock = ManualScheduleClock(start: start)
        let runner = AgentRunner(
            registry: harness.registry,
            environment: harness.environment(
                maxRetainedRuns: AgentEnvironment.defaultMaxRetainedRuns, callerMail: mailbox.route),
            scheduleClock: clock)
        return Setup(layer: layer, harness: harness, runner: runner, clock: clock, mailbox: mailbox)
    }

    /// Waits until `condition` holds, for at most five seconds.
    ///
    /// - Parameter condition: The condition.
    private static func eventually(_ condition: () async -> Bool) async {
        for _ in 0..<500 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the condition did not hold in time")
    }

    /// Makes a request of a task every minute, for the owner of `setup`.
    ///
    /// - Parameters:
    ///   - setup: The setup.
    ///   - prompt: The prompt.
    ///   - agent: The agent.
    ///   - count: The count of firings, or `nil`.
    /// - Returns: The request.
    private static func everyMinute(
        _ setup: Setup, prompt: String = pingPrompt, agent: String = agent, count: Int? = nil
    ) -> AgentScheduleRequest {
        AgentScheduleRequest(
            agent: agent, prompt: prompt, spec: .interval(seconds: 60), count: count, name: "ping", owner: setup.owner)
    }

    // MARK: - Firing

    @Test("a due firing starts a child run and mails its result with the task, its id and the firing number")
    func firingMailsTheResult() async throws {
        let setup = try await Self.makeSetup()
        defer { setup.delete() }
        let task = await setup.runner.schedule(Self.everyMinute(setup))

        setup.clock.advance(by: 60)
        await setup.runner.scheduler.tick()
        await Self.eventually { !setup.mailbox.all.isEmpty }

        let mail = try #require(setup.mailbox.all.first)
        #expect(mail.receiver == setup.owner)
        #expect(mail.text.hasPrefix("Scheduled task \"ping\" (\(task.id)), firing 1, agent \(Self.agent):"))
        #expect(mail.text.contains(Self.pong))
        let after = try #require(await setup.runner.scheduledTask(id: task.id))
        #expect(after.runCount == 1)
        #expect(after.lastResult?.contains(Self.pong) == true)
        #expect(after.nextFiring == Self.start.addingTimeInterval(120))
    }

    @Test("the timer fires a due task with no call of tick")
    func theTimerFires() async throws {
        let setup = try await Self.makeSetup()
        defer { setup.delete() }
        _ = await setup.runner.schedule(Self.everyMinute(setup))
        await Self.eventually { setup.clock.sleeperCount == 1 }

        setup.clock.advance(by: 60)

        await Self.eventually { !setup.mailbox.all.isEmpty }
    }

    @Test("a firing that is due while the previous run works is skipped, and counted")
    func overlapIsSkipped() async throws {
        let gate = ScriptedGate()
        let setup = try await Self.makeSetup(gate: gate)
        defer { setup.delete() }
        let task = await setup.runner.schedule(Self.everyMinute(setup, prompt: Self.holdPrompt))

        setup.clock.advance(by: 60)
        await setup.runner.scheduler.tick()
        setup.clock.advance(by: 60)
        await setup.runner.scheduler.tick()

        let during = try #require(await setup.runner.scheduledTask(id: task.id))
        #expect(during.runCount == 1)
        #expect(during.skippedCount == 1)

        gate.open()
        await Self.eventually { await setup.runner.scheduledTask(id: task.id)?.liveRunID == nil }
        setup.clock.advance(by: 60)
        await setup.runner.scheduler.tick()

        #expect(await setup.runner.scheduledTask(id: task.id)?.runCount == 2)
    }

    @Test("the firings of a gap run once, and count as missed")
    func gapRunsOnce() async throws {
        let setup = try await Self.makeSetup()
        defer { setup.delete() }
        let task = await setup.runner.schedule(Self.everyMinute(setup))

        setup.clock.advance(by: 300)
        await setup.runner.scheduler.tick()

        let after = try #require(await setup.runner.scheduledTask(id: task.id))
        #expect(after.runCount == 1)
        #expect(after.missedCount == 4)
        #expect(after.nextFiring == Self.start.addingTimeInterval(360))
    }

    @Test("the default agent fires, though the agents tool never starts it")
    func theDefaultAgentFires() async throws {
        let setup = try await Self.makeSetup()
        defer { setup.delete() }
        _ = await setup.runner.schedule(Self.everyMinute(setup, agent: AgentCatalog.defaultAgentID))

        setup.clock.advance(by: 60)
        await setup.runner.scheduler.tick()

        await Self.eventually { setup.mailbox.all.contains { $0.text.contains(Self.pong) } }
    }

    @Test("an unknown agent mails the corrective and starts no run")
    func unknownAgentMailsTheCorrective() async throws {
        let setup = try await Self.makeSetup()
        defer { setup.delete() }
        let task = await setup.runner.schedule(Self.everyMinute(setup, agent: "no-such-agent"))

        setup.clock.advance(by: 60)
        await setup.runner.scheduler.tick()

        let mail = try #require(setup.mailbox.all.first)
        #expect(mail.text.contains("No agent has the name no-such-agent."))
        #expect(await setup.runner.scheduledTask(id: task.id)?.liveRunID == nil)
    }

    // MARK: - The end of a task

    @Test("a recurring task with no until and no count ends after 7 days; a count ends it after its firings")
    func lifetimeAndCount() async throws {
        let setup = try await Self.makeSetup()
        defer { setup.delete() }
        let unbounded = await setup.runner.schedule(Self.everyMinute(setup))
        let counted = await setup.runner.schedule(Self.everyMinute(setup, count: 2))

        #expect(unbounded.end == Self.start.addingTimeInterval(AgentScheduledTask.defaultLifetime))
        #expect(counted.end == nil)
        for _ in 0..<2 {
            setup.clock.advance(by: 60)
            await setup.runner.scheduler.tick()
            await Self.eventually { await setup.runner.scheduledTask(id: counted.id)?.liveRunID == nil }
        }

        let ended = try #require(await setup.runner.scheduledTask(id: counted.id))
        #expect(ended.state == .ended)
        #expect(ended.runCount == 2)
        #expect(ended.nextFiring == nil)
    }

    @Test("a one-time task ends after its firing")
    func onceEnds() async throws {
        let setup = try await Self.makeSetup()
        defer { setup.delete() }
        let task = await setup.runner.schedule(
            AgentScheduleRequest(
                agent: Self.agent, prompt: Self.pingPrompt, spec: .once(Self.start.addingTimeInterval(120)),
                owner: setup.owner))

        #expect(task.end == nil)
        setup.clock.advance(by: 120)
        await setup.runner.scheduler.tick()

        #expect(await setup.runner.scheduledTask(id: task.id)?.state == .ended)
    }

    @Test("a paused task does not fire, and a resumed task skips the firings of the pause")
    func pauseAndResume() async throws {
        let setup = try await Self.makeSetup()
        defer { setup.delete() }
        let task = await setup.runner.schedule(Self.everyMinute(setup))

        await setup.runner.pauseSchedule(id: task.id)
        setup.clock.advance(by: 180)
        await setup.runner.scheduler.tick()
        #expect(await setup.runner.scheduledTask(id: task.id)?.runCount == 0)

        let resumed = try #require(await setup.runner.resumeSchedule(id: task.id))
        #expect(resumed.state == .active)
        #expect(resumed.nextFiring == Self.start.addingTimeInterval(240))
    }

    @Test("run now fires a task at once and keeps its schedule")
    func runNow() async throws {
        let setup = try await Self.makeSetup()
        defer { setup.delete() }
        let task = await setup.runner.schedule(Self.everyMinute(setup))

        let firing = await setup.runner.scheduler.runNow(id: task.id)

        guard case .started = firing else {
            Issue.record("run now did not start a run: \(firing)")
            return
        }
        await Self.eventually { !setup.mailbox.all.isEmpty }
        #expect(await setup.runner.scheduledTask(id: task.id)?.nextFiring == Self.start.addingTimeInterval(60))
    }

    @Test("closing the owner session ends and removes its tasks")
    func sessionCloseEndsTheTasks() async throws {
        let setup = try await Self.makeSetup()
        defer { setup.delete() }
        let other = ULID()
        _ = await setup.runner.schedule(Self.everyMinute(setup))
        var otherRequest = Self.everyMinute(setup)
        otherRequest.owner = other
        _ = await setup.runner.schedule(otherRequest)

        await setup.runner.cancelRuns(caller: setup.owner)

        #expect(await setup.runner.scheduledTasks(owner: setup.owner).isEmpty)
        #expect(await setup.runner.scheduledTasks(owner: other).count == 1)
    }

    // MARK: - Work

    @Test("a pending task holds no work; a running firing holds one lease of its owner")
    func workLease() async throws {
        let gate = ScriptedGate()
        let setup = try await Self.makeSetup(gate: gate)
        defer { setup.delete() }
        let work = WorkRegistry(sessionID: setup.owner)
        _ = await setup.runner.schedule(
            Self.everyMinute(setup, prompt: Self.holdPrompt), workSite: { work.begin(.childSession, id: $0) })

        #expect(!work.hasWork)
        setup.clock.advance(by: 60)
        await setup.runner.scheduler.tick()
        #expect(work.hasWork)

        gate.open()
        await Self.eventually { !work.hasWork }
    }
}
