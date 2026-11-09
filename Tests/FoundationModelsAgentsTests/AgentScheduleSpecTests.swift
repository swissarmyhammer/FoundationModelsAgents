import Foundation
@testable import FoundationModelsAgents
import Testing

/// Pins the direct forms of a schedule text: a cron expression, an ISO date
/// and time, and an interval. No model reads these forms.
@Suite("Agent schedule spec")
struct AgentScheduleSpecTests {
    /// The time zone of the tests.
    private static let zone = TimeZone(identifier: "America/New_York")!

    /// The current time of the tests: Monday 2026-11-09 08:30 in ``zone``.
    private static let now = date("2026-11-09T08:30:00-05:00")

    /// Reads an ISO 8601 date and time with a zone.
    ///
    /// - Parameter text: The text.
    /// - Returns: The date.
    private static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    /// Parses `text` and requires a spec.
    ///
    /// - Parameter text: The schedule text.
    /// - Returns: The spec.
    private static func spec(_ text: String) throws -> AgentScheduleSpec {
        guard case .parsed(let spec) = AgentScheduleSpec.parse(text, timeZone: zone, now: now) else {
            Issue.record("'\(text)' did not parse: \(AgentScheduleSpec.parse(text, timeZone: zone, now: now))")
            throw CancellationError()
        }
        return spec
    }

    /// Gives the next `count` firings of `spec` after ``now``.
    ///
    /// - Parameters:
    ///   - spec: The spec.
    ///   - count: The count of firings.
    /// - Returns: The firings.
    private static func firings(of spec: AgentScheduleSpec, count: Int) -> [Date] {
        spec.firings(after: now, anchor: now, timeZone: zone, count: count)
    }

    // MARK: - Cron

    @Test("a weekday cron fires at 9:00 on the next three weekdays")
    func weekdayCron() throws {
        let spec = try Self.spec("0 9 * * 1-5")

        #expect(spec.normalized(timeZone: Self.zone) == "0 9 * * 1-5")
        #expect(
            Self.firings(of: spec, count: 3) == [
                Self.date("2026-11-09T09:00:00-05:00"),
                Self.date("2026-11-10T09:00:00-05:00"),
                Self.date("2026-11-11T09:00:00-05:00")
            ])
    }

    @Test("a step, a list and a weekday name parse")
    func stepsListsAndNames() throws {
        #expect(
            Self.firings(of: try Self.spec("*/15 8 * * MON"), count: 3) == [
                Self.date("2026-11-09T08:45:00-05:00"),
                Self.date("2026-11-16T08:00:00-05:00"),
                Self.date("2026-11-16T08:15:00-05:00")
            ])
        #expect(
            Self.firings(of: try Self.spec("0 12,18 * * *"), count: 2) == [
                Self.date("2026-11-09T12:00:00-05:00"),
                Self.date("2026-11-09T18:00:00-05:00")
            ])
    }

    @Test("Sunday is 0 or 7")
    func sundayIsZeroOrSeven() throws {
        let sunday = Self.date("2026-11-15T10:00:00-05:00")

        #expect(Self.firings(of: try Self.spec("0 10 * * 0"), count: 1) == [sunday])
        #expect(Self.firings(of: try Self.spec("0 10 * * 7"), count: 1) == [sunday])
    }

    @Test("a restricted day of month and day of week match either")
    func dayOfMonthOrDayOfWeek() throws {
        // The 15th (a Sunday) or a Friday: Friday 13th comes first.
        #expect(
            Self.firings(of: try Self.spec("0 0 15 * 5"), count: 2) == [
                Self.date("2026-11-13T00:00:00-05:00"),
                Self.date("2026-11-15T00:00:00-05:00")
            ])
    }

    @Test("a macro is a cron expression")
    func macros() throws {
        #expect(try Self.spec("@daily").normalized(timeZone: Self.zone) == "0 0 * * *")
        #expect(try Self.spec("@hourly").normalized(timeZone: Self.zone) == "0 * * * *")
    }

    @Test("a cron with a seconds field, or a bad field, is refused")
    func badCron() {
        guard case .refused(let seconds) = AgentScheduleSpec.parse("*/10 * * * * *", timeZone: Self.zone, now: Self.now)
        else {
            Issue.record("a six-field cron was not refused")
            return
        }
        #expect(seconds.contains("1 minute"))
        guard case .refused = AgentScheduleSpec.parse("61 * * * *", timeZone: Self.zone, now: Self.now) else {
            Issue.record("minute 61 was not refused")
            return
        }
    }

    // MARK: - Once

    @Test("an ISO time with a zone fires one time")
    func onceWithZone() throws {
        let spec = try Self.spec("2026-11-09T14:00:00Z")

        #expect(Self.firings(of: spec, count: 3) == [Self.date("2026-11-09T09:00:00-05:00")])
        #expect(spec.normalized(timeZone: Self.zone) == "2026-11-09T09:00:00-05:00")
        #expect(!spec.isRecurring)
    }

    @Test("an ISO time with no zone is read in the time zone of the task")
    func onceWithoutZone() throws {
        #expect(Self.firings(of: try Self.spec("2026-11-10 07:15"), count: 1) == [Self.date("2026-11-10T07:15:00-05:00")])
        #expect(
            Self.firings(of: try Self.spec("2026-11-10T07:15:30"), count: 1) == [Self.date("2026-11-10T07:15:30-05:00")])
    }

    @Test("a one-time schedule in the past is refused")
    func onceInThePast() {
        guard case .refused(let reason) = AgentScheduleSpec.parse("2026-11-09T08:00", timeZone: Self.zone, now: Self.now)
        else {
            Issue.record("a past time was not refused")
            return
        }
        #expect(reason.contains("past"))
    }

    // MARK: - Interval

    @Test("an interval fires from the anchor, at each step")
    func interval() throws {
        let spec = try Self.spec("every 10 minutes")

        #expect(spec.normalized(timeZone: Self.zone) == "every 10 minutes")
        #expect(
            Self.firings(of: spec, count: 3) == [
                Self.date("2026-11-09T08:40:00-05:00"),
                Self.date("2026-11-09T08:50:00-05:00"),
                Self.date("2026-11-09T09:00:00-05:00")
            ])
        #expect(try Self.spec("Every hour").normalized(timeZone: Self.zone) == "every 1 hour")
        #expect(try Self.spec("every 2 days").normalized(timeZone: Self.zone) == "every 2 days")
        #expect(try Self.spec("every 90 seconds").normalized(timeZone: Self.zone) == "every 90 seconds")
    }

    @Test("an interval below one minute is refused, with the reason")
    func intervalBelowOneMinute() {
        guard case .refused(let reason) = AgentScheduleSpec.parse("every 30 seconds", timeZone: Self.zone, now: Self.now)
        else {
            Issue.record("a 30 second interval was not refused")
            return
        }
        #expect(reason.contains("1 minute"))
        #expect(reason.contains("agent run"))
    }

    // MARK: - Not direct

    @Test("English is not a direct form")
    func englishIsNotDirect() {
        for text in ["weekdays at 9", "in two hours", "tomorrow morning", "every day at 9 am"] {
            guard case .notDirect = AgentScheduleSpec.parse(text, timeZone: Self.zone, now: Self.now) else {
                Issue.record("'\(text)' was read directly")
                continue
            }
        }
    }

    // MARK: - Codable

    @Test("each form survives a JSON round trip")
    func codable() throws {
        for text in ["0 9 * * 1-5", "2026-11-10T07:15:00Z", "every 10 minutes"] {
            let spec = try Self.spec(text)
            let decoded = try JSONDecoder().decode(AgentScheduleSpec.self, from: JSONEncoder().encode(spec))
            #expect(decoded == spec)
        }
    }
}
