import Foundation

/// A cron expression of five fields: minute, hour, day of the month, month,
/// and day of the week.
///
/// Each field takes `*`, a number, a range `a-b`, a list `a,b`, and a step
/// `*/n` or `a-b/n`. The month takes `JAN`-`DEC` and the day of the week
/// takes `SUN`-`SAT`, in any case. Sunday is 0 or 7. When the day of the
/// month and the day of the week are both restricted, a day that matches
/// either fires (the rule of Vixie cron). The macros `@yearly`,
/// `@annually`, `@monthly`, `@weekly`, `@daily`, `@midnight` and `@hourly`
/// give their five-field forms.
///
/// The shortest step of a cron expression is one minute, thus each cron
/// expression obeys the shortest interval of a schedule.
public struct CronExpression: Sendable, Equatable, Codable {
    /// Why a text is not a cron expression.
    enum ParseError: Error, Equatable {
        /// The text is not a cron expression at all: it does not have five
        /// fields of cron characters.
        case notCron

        /// The text has six fields: a seconds field.
        case secondsField

        /// A field of the text is not valid, with the reason.
        case invalid(String)
    }

    /// The text of the expression, in its five-field form.
    public let text: String

    /// The minutes that fire, 0-59.
    let minutes: Set<Int>

    /// The hours that fire, 0-23.
    let hours: Set<Int>

    /// The days of the month that fire, 1-31.
    let daysOfMonth: Set<Int>

    /// The months that fire, 1-12.
    let months: Set<Int>

    /// The days of the week that fire, 0-6 with Sunday as 0.
    let daysOfWeek: Set<Int>

    /// `true` when the day-of-month field is not `*`.
    let restrictsDayOfMonth: Bool

    /// `true` when the day-of-week field is not `*`.
    let restrictsDayOfWeek: Bool

    /// The five-field form of each macro.
    private static let macros = [
        "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *", "@weekly": "0 0 * * 0",
        "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@hourly": "0 * * * *"
    ]

    /// The names of the months, January first.
    private static let monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// The names of the days of the week, Sunday first.
    private static let weekdayNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    /// The characters of a cron field.
    private static let fieldCharacters = CharacterSet(charactersIn: "0123456789*,-/?")
        .union(.letters)

    /// The most days that a search for the next firing reads: past this, the
    /// expression never fires, for example `0 0 31 2 *`.
    private static let searchDayLimit = 366 * 8

    /// Parses `text` as a cron expression.
    ///
    /// - Parameter text: The text.
    /// - Throws: ``ParseError``.
    init(parsing text: String) throws(ParseError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = Self.macros[trimmed.lowercased()] ?? trimmed
        let fields = expanded.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.allSatisfy({ $0.unicodeScalars.allSatisfy(Self.fieldCharacters.contains) }),
            fields.contains(where: { $0.contains(where: \.isNumber) || $0.contains("*") }),
            fields.allSatisfy(Self.namesAreKnown)
        else {
            throw .notCron
        }
        guard fields.count != 6 else { throw .secondsField }
        guard fields.count == 5 else { throw .notCron }
        let dayOfWeek = try Self.values(of: fields[4], in: 0...7, names: Self.weekdayNames, nameBase: 0, field: "day of week")
        self.text = fields.joined(separator: " ")
        minutes = try Self.values(of: fields[0], in: 0...59, field: "minute")
        hours = try Self.values(of: fields[1], in: 0...23, field: "hour")
        daysOfMonth = try Self.values(of: fields[2], in: 1...31, field: "day of month")
        months = try Self.values(of: fields[3], in: 1...12, names: Self.monthNames, nameBase: 1, field: "month")
        daysOfWeek = Set(dayOfWeek.map { $0 % 7 })
        restrictsDayOfMonth = !Self.isWildcard(fields[2])
        restrictsDayOfWeek = !Self.isWildcard(fields[4])
    }

    /// Tells whether each run of letters of a field is a month or a weekday
    /// name. A field with other words is English, not cron, for example the
    /// `day` of `every day at 9 am`.
    ///
    /// - Parameter field: The field.
    /// - Returns: `true` when the field has no other word.
    private static func namesAreKnown(_ field: String) -> Bool {
        field.split(whereSeparator: { !$0.isLetter }).allSatisfy { word in
            let name = word.uppercased()
            return monthNames.contains(name) || weekdayNames.contains(name)
        }
    }

    /// Tells whether a field matches each value.
    ///
    /// - Parameter field: The field.
    /// - Returns: `true` for `*` and `?`.
    private static func isWildcard(_ field: String) -> Bool {
        field == "*" || field == "?"
    }

    /// Reads the values of one field.
    ///
    /// - Parameters:
    ///   - field: The text of the field.
    ///   - range: The valid values.
    ///   - names: The names of the values, or none.
    ///   - nameBase: The value of the first name.
    ///   - field: The name of the field, for the reason of an error.
    /// - Returns: The values.
    /// - Throws: ``ParseError/invalid(_:)``.
    private static func values(
        of text: String, in range: ClosedRange<Int>, names: [String] = [], nameBase: Int = 0, field: String
    ) throws(ParseError) -> Set<Int> {
        var values: Set<Int> = []
        for part in text.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            let pieces = part.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard pieces.count <= 2, let base = pieces.first else {
                throw .invalid("the \(field) field '\(text)' is not valid")
            }
            var step = 1
            if pieces.count == 2 {
                guard let parsed = Int(pieces[1]), parsed >= 1 else {
                    throw .invalid("the step of the \(field) field '\(text)' is not a positive number")
                }
                step = parsed
            }
            let bounds: ClosedRange<Int>
            if isWildcard(base) {
                bounds = range
            } else {
                let ends = base.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                guard (1...2).contains(ends.count) else {
                    throw .invalid("the \(field) field '\(text)' is not valid")
                }
                let low = try value(of: ends[0], in: range, names: names, nameBase: nameBase, field: field)
                let high = ends.count == 2
                    ? try value(of: ends[1], in: range, names: names, nameBase: nameBase, field: field)
                    : (pieces.count == 2 ? range.upperBound : low)
                guard low <= high else {
                    throw .invalid("the range '\(base)' of the \(field) field goes down")
                }
                bounds = low...high
            }
            values.formUnion(stride(from: bounds.lowerBound, through: bounds.upperBound, by: step))
        }
        return values
    }

    /// Reads one value of a field: a number or a name.
    ///
    /// - Parameters:
    ///   - text: The text of the value.
    ///   - range: The valid values.
    ///   - names: The names of the values, or none.
    ///   - nameBase: The value of the first name.
    ///   - field: The name of the field, for the reason of an error.
    /// - Returns: The value.
    /// - Throws: ``ParseError/invalid(_:)``.
    private static func value(
        of text: String, in range: ClosedRange<Int>, names: [String], nameBase: Int, field: String
    ) throws(ParseError) -> Int {
        if let index = names.firstIndex(of: text.uppercased()) {
            return index + nameBase
        }
        guard let number = Int(text), range.contains(number) else {
            throw .invalid(
                "the \(field) field has '\(text)'; it takes \(range.lowerBound)-\(range.upperBound)")
        }
        return number
    }

    /// Gives the first time after `date` that the expression fires.
    ///
    /// - Parameters:
    ///   - date: The time to search after. The result is later than it.
    ///   - timeZone: The time zone that the fields are read in.
    /// - Returns: The time, or `nil` when the expression never fires.
    func next(after date: Date, in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.date(byAdding: .minute, value: 1, to: date).flatMap { minute in
            calendar.dateInterval(of: .minute, for: minute)?.start
        }
        guard let start, var day = calendar.dateInterval(of: .day, for: start)?.start else { return nil }
        for _ in 0..<Self.searchDayLimit {
            if matches(day: day, in: calendar), let time = firstTime(on: day, notBefore: start, in: calendar) {
                return time
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = nextDay
        }
        return nil
    }

    /// Tells whether the expression fires on the day that starts at `day`.
    ///
    /// - Parameters:
    ///   - day: The start of the day.
    ///   - calendar: The calendar in the time zone of the task.
    /// - Returns: `true` when the month and the day rules match.
    private func matches(day: Date, in calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.month, .day, .weekday], from: day)
        guard let month = parts.month, let dayOfMonth = parts.day, let weekday = parts.weekday,
            months.contains(month)
        else {
            return false
        }
        let monthMatches = daysOfMonth.contains(dayOfMonth)
        let weekMatches = daysOfWeek.contains(weekday - 1)
        if restrictsDayOfMonth && restrictsDayOfWeek {
            return monthMatches || weekMatches
        }
        return monthMatches && weekMatches
    }

    /// Gives the first time on `day` that the hour and minute rules match,
    /// at or after `notBefore`.
    ///
    /// - Parameters:
    ///   - day: The start of the day.
    ///   - notBefore: The earliest time.
    ///   - calendar: The calendar in the time zone of the task.
    /// - Returns: The time, or `nil` when no time of the day is left.
    private func firstTime(on day: Date, notBefore: Date, in calendar: Calendar) -> Date? {
        for hour in hours.sorted() {
            for minute in minutes.sorted() {
                guard
                    let time = calendar.date(
                        bySettingHour: hour, minute: minute, second: 0, of: day, matchingPolicy: .nextTime,
                        repeatedTimePolicy: .first, direction: .forward),
                    calendar.isDate(time, inSameDayAs: day)
                else {
                    continue
                }
                if time >= notBefore {
                    return time
                }
            }
        }
        return nil
    }

    // MARK: - Codable

    /// Decodes the expression from its text.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: A decoding error when the text is not a cron expression.
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        do {
            try self.init(parsing: text)
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "not a cron expression: \(text)"))
        }
    }

    /// Encodes the expression as its text.
    ///
    /// - Parameter encoder: The encoder.
    /// - Throws: The error of the encoder.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}
