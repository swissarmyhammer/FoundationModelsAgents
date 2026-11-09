import Foundation

/// When a scheduled agent fires: a cron expression, one time, or a fixed
/// interval.
///
/// ``parse(_:timeZone:now:)`` reads the three direct forms of a schedule text
/// with no model. A text in English gives ``Parse/notDirect``, and the
/// normalizer of the scheduler changes it into a direct form first.
public enum AgentScheduleSpec: Sendable, Equatable, Codable {
    /// A cron expression, read in the time zone of the task.
    case cron(CronExpression)

    /// One time.
    case once(Date)

    /// A fixed interval in seconds, counted from the anchor of the task:
    /// the time that the task was made.
    case interval(seconds: Int)

    /// What ``parse(_:timeZone:now:)`` gives.
    public enum Parse: Sendable, Equatable {
        /// The text is a direct form.
        case parsed(AgentScheduleSpec)

        /// The text is a direct form that a schedule cannot take, with the
        /// reason.
        case refused(String)

        /// The text is not a direct form.
        case notDirect
    }

    /// The shortest interval of a schedule, in seconds: one minute.
    public static let shortestInterval = 60

    /// The reason of each refusal of a schedule faster than
    /// ``shortestInterval``.
    static let tooFastReason = """
        The shortest schedule is 1 minute, because each firing is an agent run on one shared model.
        """

    /// The seconds of each interval unit, by the words of the unit.
    private static let unitSeconds: [(words: Set<String>, seconds: Int, name: String)] = [
        (["second", "seconds", "sec", "secs", "s"], 1, "second"),
        (["minute", "minutes", "min", "mins", "m"], 60, "minute"),
        (["hour", "hours", "hr", "hrs", "h"], 3600, "hour"),
        (["day", "days", "d"], 86_400, "day")
    ]

    /// The forms of an ISO 8601 date and time with no time zone.
    private static let localTimeFormats = [
        "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"
    ]

    /// `true` for a schedule that fires more than one time.
    public var isRecurring: Bool {
        if case .once = self { return false }
        return true
    }

    // MARK: - Parse

    /// Reads a direct form of a schedule text.
    ///
    /// - Parameters:
    ///   - text: The schedule text.
    ///   - timeZone: The time zone of the task. A time with no zone is read
    ///     in it.
    ///   - now: The current time. A one-time schedule must be later.
    /// - Returns: The spec, a refusal with its reason, or
    ///   ``Parse/notDirect``.
    public static func parse(_ text: String, timeZone: TimeZone, now: Date) -> Parse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let interval = parseInterval(trimmed) {
            return interval
        }
        if let date = parseDate(trimmed, timeZone: timeZone) {
            guard date > now else {
                return .refused("The time \(formatted(date, in: timeZone)) is in the past.")
            }
            return .parsed(.once(date))
        }
        do {
            return .parsed(.cron(try CronExpression(parsing: trimmed)))
        } catch {
            switch error {
            case .notCron:
                return .notDirect
            case .secondsField:
                return .refused("A cron expression with a seconds field is not supported. \(tooFastReason)")
            case .invalid(let reason):
                return .refused("The cron expression is not valid: \(reason).")
            }
        }
    }

    /// Reads `every N unit`, or `every unit` for N = 1.
    ///
    /// - Parameter text: The trimmed text.
    /// - Returns: The interval, a refusal for an interval below one minute,
    ///   or `nil` when the text is not an interval.
    private static func parseInterval(_ text: String) -> Parse? {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.first == "every", (2...3).contains(words.count) else { return nil }
        let count = words.count == 3 ? Int(words[1]) : 1
        guard let count, count >= 1, let unit = unitSeconds.first(where: { $0.words.contains(words[words.count - 1]) })
        else {
            return nil
        }
        let seconds = count * unit.seconds
        guard seconds >= shortestInterval else {
            return .refused(tooFastReason)
        }
        return .parsed(.interval(seconds: seconds))
    }

    /// Reads an ISO 8601 date and time, with a zone or in `timeZone`.
    ///
    /// - Parameters:
    ///   - text: The trimmed text.
    ///   - timeZone: The time zone of a time with no zone.
    /// - Returns: The date, or `nil` when the text is not a date and time.
    static func parseDate(_ text: String, timeZone: TimeZone) -> Date? {
        let zoned = ISO8601DateFormatter()
        if let date = zoned.date(from: text) {
            return date
        }
        zoned.formatOptions.insert(.withFractionalSeconds)
        if let date = zoned.date(from: text) {
            return date
        }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = timeZone
        for format in localTimeFormats {
            local.dateFormat = format
            if let date = local.date(from: text) {
                return date
            }
        }
        return nil
    }

    // MARK: - Firings

    /// Gives the first time after `date` that the schedule fires.
    ///
    /// - Parameters:
    ///   - date: The time to search after. The result is later than it.
    ///   - anchor: The time that an interval counts from.
    ///   - timeZone: The time zone of the task.
    /// - Returns: The time, or `nil` when the schedule does not fire again.
    public func next(after date: Date, anchor: Date, timeZone: TimeZone) -> Date? {
        switch self {
        case .cron(let expression):
            return expression.next(after: date, in: timeZone)
        case .once(let time):
            return time > date ? time : nil
        case .interval(let seconds):
            let step = TimeInterval(seconds)
            guard date >= anchor else { return anchor.addingTimeInterval(step) }
            let steps = (date.timeIntervalSince(anchor) / step).rounded(.down) + 1
            return anchor.addingTimeInterval(steps * step)
        }
    }

    /// Gives the next `count` times after `date` that the schedule fires.
    ///
    /// - Parameters:
    ///   - date: The time to search after.
    ///   - anchor: The time that an interval counts from.
    ///   - timeZone: The time zone of the task.
    ///   - count: The most times to give.
    /// - Returns: The times, earliest first. Fewer than `count` when the
    ///   schedule stops.
    public func firings(after date: Date, anchor: Date, timeZone: TimeZone, count: Int) -> [Date] {
        var times: [Date] = []
        var cursor = date
        while times.count < count, let time = next(after: cursor, anchor: anchor, timeZone: timeZone) {
            times.append(time)
            cursor = time
        }
        return times
    }

    // MARK: - Text

    /// The normalized text of the schedule: the five-field cron text, the
    /// ISO 8601 time in `timeZone`, or `every N unit`.
    ///
    /// - Parameter timeZone: The time zone of the task.
    /// - Returns: The text.
    public func normalized(timeZone: TimeZone) -> String {
        switch self {
        case .cron(let expression):
            return expression.text
        case .once(let date):
            return Self.formatted(date, in: timeZone)
        case .interval(let seconds):
            let unit = Self.unitSeconds.reversed().first { seconds % $0.seconds == 0 } ?? Self.unitSeconds[0]
            let count = seconds / unit.seconds
            return "every \(count) \(unit.name)\(count == 1 ? "" : "s")"
        }
    }

    /// Formats `date` as an ISO 8601 time with the offset of `timeZone`.
    ///
    /// - Parameters:
    ///   - date: The time.
    ///   - timeZone: The time zone.
    /// - Returns: The text, for example `2026-11-09T09:00:00-05:00`.
    static func formatted(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.string(from: date)
    }
}
