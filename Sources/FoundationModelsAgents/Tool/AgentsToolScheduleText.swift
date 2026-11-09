import Foundation

/// The answers of the schedule operations of the `agents` tool.
enum AgentsToolScheduleText {
    /// The count of next firings that a new task shows.
    static let shownFiringCount = 3

    /// The most characters of the last result that `list schedules` shows.
    static let shortResultLimit = 80

    /// The answer of `list schedules` with no task.
    static let noSchedules = "You have no scheduled agents."

    /// The corrective for a `count` below one.
    static let countBelowOne = "The count must be 1 or more. Leave it out for no count."

    /// The corrective for an id that names no task of the session.
    ///
    /// - Parameter id: The id that the model gave.
    /// - Returns: The text.
    static func unknownSchedule(_ id: String) -> String {
        "No scheduled agent of yours has the id \(id). Use {\"op\": \"list schedules\"} to see your scheduled agents."
    }

    /// The corrective for a time zone that is not known.
    ///
    /// - Parameter identifier: The identifier that the model gave.
    /// - Returns: The text.
    static func unknownTimeZone(_ identifier: String) -> String {
        "The time zone \(identifier) is not known. Give an IANA name, for example America/New_York or UTC."
    }

    /// The corrective for an `until` that is not a date and time.
    ///
    /// - Parameter text: The text that the model gave.
    /// - Returns: The text.
    static func badUntil(_ text: String) -> String {
        "The until value '\(text)' is not a date and time. Give an ISO time, for example 2026-11-20T18:00."
    }

    /// The corrective for an `until` in the past.
    ///
    /// - Parameter text: The text that the model gave.
    /// - Returns: The text.
    static func pastUntil(_ text: String) -> String {
        "The until time \(text) is in the past."
    }

    /// The answer of `schedule agent`: the task, the normalized schedule, the
    /// time zone, the next firings and the end.
    ///
    /// - Parameters:
    ///   - task: The new task.
    ///   - now: The current time.
    /// - Returns: The text.
    static func created(_ task: AgentScheduledTask, now: Date) -> String {
        let read = task.english.map { ", read from \"\($0)\"" } ?? ""
        let firings = task.upcoming(after: now, count: shownFiringCount)
            .map { "- \(AgentScheduleSpec.formatted($0, in: task.timeZone))" }
        return ([
            "Scheduled task \"\(task.name)\" (\(task.id)): agent \(task.agent).",
            "Schedule: \(task.schedule) (\(task.timeZoneIdentifier))\(read).",
            "Next firings:"
        ] + firings + [
            "Ends: \(end(of: task)).",
            "Each firing runs the agent in a new run. Its result comes to you as mail after each firing."
        ]).joined(separator: "\n")
    }

    /// One line of `list schedules`.
    ///
    /// - Parameter task: The task.
    /// - Returns: The line.
    static func line(of task: AgentScheduledTask) -> String {
        let next = task.nextFiring.map { AgentScheduleSpec.formatted($0, in: task.timeZone) } ?? "none"
        return "- \(task.id) \"\(task.name)\": agent \(task.agent), \(task.schedule) (\(task.timeZoneIdentifier)), "
            + "\(state(of: task)), next \(next), runs \(task.runCount), skipped \(task.skippedCount), "
            + "missed \(task.missedCount), ends \(end(of: task)), last: \(shortResult(of: task))"
    }

    /// The answer of `list schedules`.
    ///
    /// - Parameter tasks: The tasks of the session.
    /// - Returns: The text.
    static func listing(of tasks: [AgentScheduledTask]) -> String {
        tasks.isEmpty ? noSchedules : tasks.map(line(of:)).joined(separator: "\n")
    }

    /// The answer of `get schedule`, `pause schedule`, `resume schedule` and
    /// `cancel schedule`: the line of the task, its prompt and its full last
    /// result.
    ///
    /// - Parameter task: The task.
    /// - Returns: The text.
    static func detail(of task: AgentScheduledTask) -> String {
        [line(of: task), "Prompt: \(task.prompt)", "Last result: \(task.lastResult ?? "none")"]
            .joined(separator: "\n")
    }

    /// The answer of `run schedule`.
    ///
    /// - Parameters:
    ///   - firing: What the firing did.
    ///   - task: The task.
    /// - Returns: The text.
    static func ran(_ firing: AgentScheduleFiring, of task: AgentScheduledTask) -> String {
        switch firing {
        case .started(let runID):
            "The scheduled agent \"\(task.name)\" started the run \(runID). Its result comes to you as mail."
        case .skipped:
            "The scheduled agent \"\(task.name)\" did not start: the run of its last firing still works."
        case .failed(let reason):
            "The scheduled agent \"\(task.name)\" did not start: \(reason)"
        case .notFound:
            "The scheduled agent \"\(task.name)\" has ended and does not run."
        }
    }

    /// The state of a task, with the reason of its end.
    ///
    /// - Parameter task: The task.
    /// - Returns: The text.
    private static func state(of task: AgentScheduledTask) -> String {
        guard task.state == .ended, let reason = task.endReason else { return task.state.rawValue }
        return "ended (\(reason))"
    }

    /// The end of a task.
    ///
    /// - Parameter task: The task.
    /// - Returns: The time of the end, the count of firings, or the one firing.
    private static func end(of task: AgentScheduledTask) -> String {
        if let end = task.end {
            return AgentScheduleSpec.formatted(end, in: task.timeZone)
        }
        if let maxRuns = task.maxRuns {
            return "after \(maxRuns) firing\(maxRuns == 1 ? "" : "s")"
        }
        return task.spec.isRecurring ? "never" : "after its one firing"
    }

    /// The short last result of a task: its first line, cut to
    /// ``shortResultLimit`` characters.
    ///
    /// - Parameter task: The task.
    /// - Returns: The text.
    private static func shortResult(of task: AgentScheduledTask) -> String {
        guard let result = task.lastResult else { return "none" }
        let firstLine = result.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return firstLine.count > shortResultLimit ? String(firstLine.prefix(shortResultLimit)) + "…" : firstLine
    }
}
