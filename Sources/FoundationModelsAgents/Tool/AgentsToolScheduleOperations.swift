import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations
import ULID

/// Schedules an agent on a timer (`schedule agent`).
///
/// Each firing starts the agent in a new child run of the calling session,
/// and the result of each firing comes to that session as mail.
@Generable
@Operation(
    verb: "schedule", noun: "agent",
    description: "Run an agent on a schedule. Each firing is a new run, and its result comes to you as mail.")
struct ScheduleAgent {
    /// The schedule text.
    @Guide(
        description: """
            When to run: a 5-field cron expression (0 9 * * 1-5), one ISO date and time \
            (2026-11-10T09:00), an interval (every 10 minutes), or plain English (weekdays at 9 AM). \
            The shortest schedule is 1 minute.
            """)
    @OperationParam(aliases: ["cron", "when", "at", "every", "interval", "frequency", "recurrence", "spec", "expression", "time", "timing"])
    var schedule: String

    /// The task of each firing.
    @Guide(description: "The full task of each firing. The agent sees only this text.")
    @OperationParam(aliases: ["task", "message", "instructions", "instruction", "text", "query", "job"])
    var prompt: String

    /// The agent of each firing, or `nil` for the default agent.
    @Guide(description: "Optional. The name of the agent to run. Leave it out to run the default agent.")
    @OperationParam(aliases: ["name", "agentName", "agentID", "agentId", "subagent", "subagentType", "agentType", "worker"])
    var agent: String?

    /// The end of a recurring task, or `nil`.
    @Guide(description: "Optional. An ISO date and time after which the task stops. Default: 7 days.")
    @OperationParam(aliases: ["end", "ends", "endAt", "endDate", "endTime", "expires", "expiresAt", "expiry", "stopAt", "deadline", "untilDate"])
    var until: String?

    /// The most firings of a recurring task, or `nil`.
    @Guide(description: "Optional. The most times to run.")
    @OperationParam(aliases: ["times", "repeat", "repeats", "maxRuns", "runs", "occurrences", "iterations", "limit", "maxCount"])
    var count: Int?

    /// The name of the task, or `nil` for a made name.
    @Guide(description: "Optional. A short name for the scheduled task.")
    @OperationParam(aliases: ["label", "taskName", "scheduleName", "description"])
    var title: String?

    /// The time zone, or `nil` for the local time zone.
    @Guide(description: "Optional. An IANA time zone, for example America/New_York. Default: the local time zone.")
    @OperationParam(aliases: ["tz", "zone", "timezone", "timeZoneID", "timeZoneId", "timeZoneName"])
    var timeZone: String?
}

extension ScheduleAgent {
    /// Reads the schedule, checks the agent and the limits, and adds the
    /// task for the calling session.
    ///
    /// The agent must be one that `start agent` of this tool can start, or
    /// the default agent. A schedule text in English goes to the flash slot
    /// of the profile; an ambiguous text is refused, not guessed.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The new task with its normalized schedule, its time zone,
    ///   its next 3 firings and its end. A corrective for a blank prompt, an
    ///   agent that cannot run, a depth above the limit, a schedule that
    ///   cannot be read or is faster than 1 minute, a count below one, an
    ///   unknown time zone, or an until that is not a later time.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        guard AgentDefinitionRules.holdsText(prompt) else {
            return .corrective(AgentsToolText.blankPrompt)
        }
        let agentName = agent.flatMap { AgentDefinitionRules.holdsText($0) ? $0 : nil } ?? AgentCatalog.defaultAgentID
        if let corrective = context.scheduleCorrective(forAgent: agentName) {
            return .corrective(corrective)
        }
        if let count, count < 1 {
            return .corrective(AgentsToolScheduleText.countBelowOne)
        }
        let zone: TimeZone
        if let timeZone, AgentDefinitionRules.holdsText(timeZone) {
            guard let known = TimeZone(identifier: timeZone.trimmingCharacters(in: .whitespaces)) else {
                return .corrective(AgentsToolScheduleText.unknownTimeZone(timeZone))
            }
            zone = known
        } else {
            zone = .current
        }
        let runner = context.runner
        let now = runner.scheduler.clock.now
        var end: Date?
        if let until, AgentDefinitionRules.holdsText(until) {
            guard let date = AgentScheduleSpec.parseDate(until.trimmingCharacters(in: .whitespaces), timeZone: zone)
            else {
                return .corrective(AgentsToolScheduleText.badUntil(until))
            }
            guard date > now else {
                return .corrective(AgentsToolScheduleText.pastUntil(until))
            }
            end = date
        }
        let reader = AgentScheduleReader(
            normalizer: runner.environment.selectionModel.map { ModelScheduleNormalizer(model: $0) })
        let read = await reader.read(schedule, timeZone: zone, now: now)
        guard case .parsed(let spec, let english) = read else {
            if case .refused(let reason) = read {
                return .corrective(reason)
            }
            return .corrective(AgentScheduleReader.directForms)
        }
        let task = await runner.schedule(
            AgentScheduleRequest(
                agent: agentName, prompt: prompt, spec: spec, english: english, timeZone: zone, until: end,
                count: count, name: title, owner: context.scheduleOwner, workingDirectory: context.parent?.workingDirectory),
            workSite: context.scheduleWorkSite)
        return .success(AgentsToolScheduleText.created(task, now: now))
    }
}

/// Lists the scheduled agents of the session (`list schedules`).
@Generable
@Operation(verb: "list", noun: "schedules", description: "List each scheduled agent that you made, with its state.")
struct ListSchedules {}

extension ListSchedules {
    /// Gives one line for each task of the calling session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The lines, or "You have no scheduled agents.".
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        .success(AgentsToolScheduleText.listing(of: await context.runner.scheduledTasks(owner: context.scheduleOwner)))
    }
}

/// Shows one scheduled agent (`get schedule`).
@Generable
@Operation(verb: "get", noun: "schedule", description: "Show one scheduled agent, with its prompt and its last result.")
struct GetSchedule {
    /// The id of the task.
    @Guide(description: "The id of the scheduled agent.")
    @OperationParam(aliases: ["scheduleID", "scheduleId", "taskID", "taskId", "schedule", "task", "jobID", "jobId"])
    var id: String
}

extension GetSchedule {
    /// Gives the detail of the task `id` of the calling session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The detail, or a corrective for an id that names no task of
    ///   the session.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        await context.answer(forSchedule: id) { task in .success(AgentsToolScheduleText.detail(of: task)) }
    }
}

/// Ends one scheduled agent (`cancel schedule`).
@Generable
@Operation(
    verb: "cancel", noun: "schedule",
    description: "Stop a scheduled agent for good. A run that works now goes on.")
struct CancelSchedule {
    /// The id of the task.
    @Guide(description: "The id of the scheduled agent.")
    @OperationParam(aliases: ["scheduleID", "scheduleId", "taskID", "taskId", "schedule", "task", "jobID", "jobId"])
    var id: String
}

extension CancelSchedule {
    /// Ends the task `id` of the calling session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The detail of the ended task, or a corrective.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        await context.answer(forSchedule: id) { task in
            let ended = await context.runner.cancelSchedule(id: task.id) ?? task
            return .success(AgentsToolScheduleText.detail(of: ended))
        }
    }
}

/// Pauses one scheduled agent (`pause schedule`).
@Generable
@Operation(verb: "pause", noun: "schedule", description: "Pause a scheduled agent until you resume it.")
struct PauseSchedule {
    /// The id of the task.
    @Guide(description: "The id of the scheduled agent.")
    @OperationParam(aliases: ["scheduleID", "scheduleId", "taskID", "taskId", "schedule", "task", "jobID", "jobId"])
    var id: String
}

extension PauseSchedule {
    /// Pauses the task `id` of the calling session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The detail of the task, or a corrective.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        await context.answer(forSchedule: id) { task in
            let paused = await context.runner.pauseSchedule(id: task.id) ?? task
            return .success(AgentsToolScheduleText.detail(of: paused))
        }
    }
}

/// Resumes one paused scheduled agent (`resume schedule`).
@Generable
@Operation(
    verb: "resume", noun: "schedule",
    description: "Resume a paused scheduled agent. The firings of the pause do not run.")
struct ResumeSchedule {
    /// The id of the task.
    @Guide(description: "The id of the scheduled agent.")
    @OperationParam(aliases: ["scheduleID", "scheduleId", "taskID", "taskId", "schedule", "task", "jobID", "jobId"])
    var id: String
}

extension ResumeSchedule {
    /// Resumes the task `id` of the calling session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The detail of the task, or a corrective.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        await context.answer(forSchedule: id) { task in
            let resumed = await context.runner.resumeSchedule(id: task.id) ?? task
            return .success(AgentsToolScheduleText.detail(of: resumed))
        }
    }
}

/// Fires one scheduled agent now (`start schedule`). The verb alias `run`
/// of the tool gives `start`, thus `run schedule` is this operation too.
@Generable
@Operation(
    verb: "start", noun: "schedule",
    description: "Run a scheduled agent now, one time. Its schedule does not change.")
struct StartSchedule {
    /// The id of the task.
    @Guide(description: "The id of the scheduled agent.")
    @OperationParam(aliases: ["scheduleID", "scheduleId", "taskID", "taskId", "schedule", "task", "jobID", "jobId"])
    var id: String
}

extension StartSchedule {
    /// Fires the task `id` of the calling session now.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The id of the started run, or why no run started, or a
    ///   corrective.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        await context.answer(forSchedule: id) { task in
            .success(AgentsToolScheduleText.ran(await context.runner.scheduler.runNow(id: task.id), of: task))
        }
    }
}

extension AgentsToolContext {
    /// The session that owns the scheduled agents of this tool: the session
    /// of the call, or `nil` outside a Router session (the host).
    var scheduleOwner: ULID? {
        ToolContext.current?.sessionID
    }

    /// Opens the lease of a firing in the work registry of the session of the
    /// call, or `nil` outside a Router session.
    var scheduleWorkSite: AgentScheduleWorkSite? {
        guard let call = ToolContext.current else { return nil }
        return { id in call.beginBackgroundWork(.childSession, id: id) }
    }

    /// Gives the corrective for an agent that a scheduled agent cannot run,
    /// or `nil` when it can.
    ///
    /// The agent must be one that `start agent` of this tool can start, or
    /// the default agent of the catalog. The depth of a firing must be within
    /// ``AgentEnvironment/maxDepth``.
    ///
    /// - Parameter name: The name of the agent.
    /// - Returns: The corrective, or `nil`.
    func scheduleCorrective(forAgent name: String) -> String? {
        let startable = startableAgents()
        let isDefault = name == AgentCatalog.defaultAgentID && runner.registry.catalog().defaultAgent != nil
        guard isDefault || startable.contains(where: { $0.id == name }) else {
            return AgentsToolText.unknownAgent(name, available: startable.map(\.id))
        }
        let maxDepth = runner.environment.maxDepth
        guard childDepth <= maxDepth else {
            return AgentsToolText.atDepthLimit(maxDepth: maxDepth)
        }
        return nil
    }

    /// Finds the task `id` of the calling session, and gives the answer of
    /// `body` for it.
    ///
    /// - Parameters:
    ///   - id: The id that the model gave.
    ///   - body: Gives the answer for the task.
    /// - Returns: The answer of `body`, or the unknown-schedule corrective.
    func answer(
        forSchedule id: String, _ body: (AgentScheduledTask) async -> AgentsToolAnswer
    ) async -> AgentsToolAnswer {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let taskID = ULID(ulidString: trimmed.uppercased()),
            let task = await runner.scheduledTask(id: taskID), task.owner == scheduleOwner
        else {
            return .corrective(AgentsToolScheduleText.unknownSchedule(id))
        }
        return await body(task)
    }
}
