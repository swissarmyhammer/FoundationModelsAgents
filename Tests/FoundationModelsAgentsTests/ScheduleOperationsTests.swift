import Foundation
import FoundationModels
@testable import FoundationModelsAgents
import Testing
import ULID

/// Pins the schedule operations of the `agents` tool: `schedule agent`,
/// `list schedules`, `get schedule`, `pause schedule`, `resume schedule`,
/// `cancel schedule` and `start schedule` (`run schedule` by the verb alias).
@Suite("Schedule operations")
struct ScheduleOperationsTests {
    /// A model-visible agent of the fixture library.
    private static let agent = "code-reviewer"

    /// The fixture agent with `disable-model-invocation: true`.
    private static let hiddenAgent = "release-manager"

    /// The prompt of each task.
    private static let prompt = "schedule-ops: review the open changes"

    /// Calls `schedule agent` with `fields`, the prompt, and `count`.
    ///
    /// - Parameters:
    ///   - harness: The tool harness.
    ///   - fields: The text fields other than the prompt.
    ///   - count: The `count` field, or `nil` for none.
    /// - Returns: The answer.
    private static func schedule(
        _ harness: AgentsToolHarness, _ fields: [String: String], count: Int? = nil
    ) async throws -> String {
        var properties: [(String, any ConvertibleToGeneratedContent)] =
            fields.merging(["prompt": prompt, "op": "schedule agent"]) { given, _ in given }.map { ($0.key, $0.value) }
        if let count {
            properties.append(("count", count))
        }
        return try await harness.tool.call(
            arguments: GeneratedContent(properties: properties, uniquingKeysWith: { _, last in last }))
    }

    /// The id in the first line of a `schedule agent` answer.
    ///
    /// - Parameter answer: The answer.
    /// - Returns: The id.
    private static func id(in answer: String) throws -> String {
        let open = try #require(answer.firstIndex(of: "("))
        let close = try #require(answer[open...].firstIndex(of: ")"))
        return String(answer[answer.index(after: open)..<close])
    }

    // MARK: - schedule agent

    @Test("schedule agent shows the normalized schedule, the time zone, the next 3 firings and the end")
    func createAnswer() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await Self.schedule(
            harness, ["schedule": "0 9 * * *", "agent": Self.agent, "timeZone": "UTC", "title": "morning review"])

        #expect(answer.hasPrefix("Scheduled task \"morning review\" ("))
        #expect(answer.contains("Schedule: 0 9 * * * (GMT)"))
        let firingLines = answer.split(separator: "\n").filter { $0.hasPrefix("- ") && $0.hasSuffix("T09:00:00Z") }
        #expect(firingLines.count == 3)
        #expect(answer.contains("Ends: "))
        let tasks = await harness.runner.scheduledTasks(owner: nil)
        #expect(tasks.map(\.id.description) == [try Self.id(in: answer)])
        #expect(tasks.first?.agent == Self.agent)
        #expect(tasks.first?.prompt == Self.prompt)
    }

    @Test("the agent defaults to the default agent")
    func agentDefaultsToDefault() async throws {
        let layer = try TemporaryLayer.make(holding: [
            "AGENT.md": AgentFolderFixture.agentText(name: "Main"),
            AgentFolderFixture.documentPath(of: Self.agent): AgentFolderFixture.agentText(name: Self.agent)
        ])
        defer { try? layer.delete() }
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }

        let answer = try await Self.schedule(harness, ["schedule": "every 10 minutes"])

        #expect(answer.contains("agent \(AgentCatalog.defaultAgentID)"))
        #expect(await harness.runner.scheduledTasks(owner: nil).first?.agent == AgentCatalog.defaultAgentID)
    }

    @Test("a count and an until show as the end")
    func countAndUntil() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let counted = try await Self.schedule(harness, ["schedule": "every 10 minutes", "agent": Self.agent], count: 3)
        let until = try await Self.schedule(
            harness,
            ["schedule": "every 10 minutes", "agent": Self.agent, "until": "2999-01-01T00:00:00Z", "timeZone": "UTC"])

        #expect(counted.contains("Ends: after 3 firings"))
        #expect(until.contains("Ends: 2999-01-01T00:00:00Z"))
    }

    @Test("schedule agent refuses with a corrective, and makes no task")
    func refusals() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let cases: [([String: String], String)] = [
            (["schedule": "every 30 seconds", "agent": Self.agent], "1 minute"),
            (["schedule": "weekdays at 9", "agent": Self.agent], "cron"),
            (["schedule": "every 10 minutes", "agent": "no-such-agent"], "No agent has the name no-such-agent."),
            (["schedule": "every 10 minutes", "agent": Self.hiddenAgent], "No agent has the name \(Self.hiddenAgent)."),
            (["schedule": "every 10 minutes"], "No agent has the name default."),
            (["schedule": "every 10 minutes", "agent": Self.agent, "timeZone": "Mars/Base"], "Mars/Base"),
            (["schedule": "every 10 minutes", "agent": Self.agent, "until": "2001-01-01T00:00:00Z"], "past"),
            (["schedule": "every 10 minutes", "agent": Self.agent, "until": "soon"], "until")
        ]
        for (fields, expected) in cases {
            let answer = try await Self.schedule(harness, fields)
            #expect(answer.contains(expected), "\(fields) gave: \(answer)")
        }
        let zeroCount = try await Self.schedule(harness, ["schedule": "every 10 minutes", "agent": Self.agent], count: 0)
        #expect(zeroCount.contains("count"))
        let blank = try await harness.call(
            "schedule agent", ["schedule": "every 10 minutes", "agent": Self.agent, "prompt": "  "])
        #expect(blank == AgentsToolText.blankPrompt)
        #expect(await harness.runner.scheduledTasks(owner: nil).isEmpty)
    }

    // MARK: - Forgiving field names

    @Test("schedule agent takes the common other names of its fields")
    func forgivingCreateFields() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await harness.call(
            "schedule agent",
            [
                "cron": "0 9 * * *", "task": Self.prompt, "agent_name": Self.agent, "name": "nightly",
                "tz": "UTC", "end_date": "2999-01-01T00:00:00Z"
            ])

        #expect(answer.hasPrefix("Scheduled task \"nightly\" ("), "\(answer)")
        let task = try #require(await harness.runner.scheduledTasks(owner: nil).first)
        #expect(task.agent == Self.agent)
        #expect(task.prompt == Self.prompt)
        #expect(task.schedule == "0 9 * * *")
        #expect(task.timeZoneIdentifier == "GMT")
        #expect(task.end == ISO8601DateFormatter().date(from: "2999-01-01T00:00:00Z"))
    }

    @Test("the id operations take schedule_id and task_id")
    func forgivingIDFields() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }
        let id = try Self.id(
            in: try await Self.schedule(harness, ["schedule": "every 10 minutes", "agent": Self.agent]))

        let got = try await harness.call("get schedule", ["schedule_id": id])
        let paused = try await harness.call("pause schedule", ["taskId": id])

        #expect(got.contains(Self.prompt))
        #expect(paused.contains("paused"))
    }

    // MARK: - The other operations

    @Test("list schedules shows each task with its fields")
    func listSchedules() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }
        #expect(try await harness.call("list schedules") == AgentsToolScheduleText.noSchedules)
        let id = try Self.id(
            in: try await Self.schedule(
                harness, ["schedule": "every 10 minutes", "agent": Self.agent, "title": "tidy", "timeZone": "UTC"]))

        let listed = try await harness.call("list schedules")

        #expect(listed.contains(id))
        #expect(listed.contains("\"tidy\""))
        #expect(listed.contains("agent \(Self.agent)"))
        #expect(listed.contains("every 10 minutes (GMT)"))
        #expect(listed.contains("active"))
        #expect(listed.contains("next "))
        #expect(listed.contains("runs 0, skipped 0, missed 0"))
        #expect(listed.contains("ends "))
        #expect(listed.contains("last: none"))
    }

    @Test("get, pause, resume and cancel schedule change and show one task")
    func lifecycle() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }
        let id = try Self.id(
            in: try await Self.schedule(harness, ["schedule": "every 10 minutes", "agent": Self.agent]))

        let got = try await harness.call("get schedule", ["id": id])
        let paused = try await harness.call("pause schedule", ["id": id])
        let pausedState = await harness.runner.scheduledTasks(owner: nil).first?.state
        let resumed = try await harness.call("resume schedule", ["id": id])
        let cancelled = try await harness.call("cancel schedule", ["id": id])

        #expect(got.contains(Self.prompt))
        #expect(paused.contains("paused"))
        #expect(pausedState == .paused)
        #expect(resumed.contains("active"))
        #expect(cancelled.contains("ended"))
        #expect(await harness.runner.scheduledTasks(owner: nil).first?.state == .ended)
    }

    @Test("an id that names no task of the session gives a corrective")
    func unknownID() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }
        let other = await harness.runner.schedule(
            AgentScheduleRequest(agent: Self.agent, prompt: Self.prompt, spec: .interval(seconds: 600), owner: ULID()))

        for operation in ["get schedule", "pause schedule", "resume schedule", "cancel schedule", "run schedule"] {
            let answer = try await harness.call(operation, ["id": other.id.description])
            #expect(answer == AgentsToolScheduleText.unknownSchedule(other.id.description), "\(operation)")
        }
    }

    @Test("run schedule fires a task now")
    func runSchedule() async throws {
        let harness = try await AgentsToolHarness.make(
            script: ScriptedAgentScript([ScriptedAgentPlay(key: Self.prompt, steps: [.finalText("reviewed")])]))
        defer { try? harness.delete() }
        let id = try Self.id(
            in: try await Self.schedule(harness, ["schedule": "every 10 minutes", "agent": Self.agent]))

        let answer = try await harness.call("run schedule", ["id": id])

        #expect(answer.contains("started"))
        #expect(await harness.runner.scheduledTasks(owner: nil).first?.runCount == 1)
    }
}
