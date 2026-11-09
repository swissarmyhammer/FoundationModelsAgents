import Foundation
import FoundationModels

/// The answer of a normalizer: one direct form of the schedule, or the
/// reason that the text is ambiguous.
@Generable
public struct AgentScheduleNormalization: Sendable, Equatable {
    /// The schedule as one direct form, or empty when the text is ambiguous.
    @Guide(
        description: """
            The schedule as exactly one of: a 5-field cron expression (minute hour day-of-month month \
            day-of-week); a local date and time yyyy-MM-ddTHH:mm for one time; or every N minutes, \
            every N hours, every N days. Empty when the text is ambiguous.
            """)
    public var schedule: String

    /// Why the text is ambiguous, or empty when it is not.
    @Guide(
        description: """
            Empty when the text means one schedule. Else one short sentence that tells what is \
            missing or has two meanings, for example: 'at 9' can be 9 AM or 9 PM.
            """)
    public var ambiguity: String

    /// Makes an answer.
    ///
    /// - Parameters:
    ///   - schedule: The schedule as one direct form, or empty.
    ///   - ambiguity: Why the text is ambiguous, or empty.
    public init(schedule: String, ambiguity: String = "") {
        self.schedule = schedule
        self.ambiguity = ambiguity
    }
}

/// Changes an English schedule text into a direct form.
public protocol AgentScheduleNormalizing: Sendable {
    /// Normalizes `text`.
    ///
    /// - Parameters:
    ///   - text: The English schedule text.
    ///   - timeZone: The time zone of the task.
    ///   - now: The current time.
    /// - Returns: One direct form, or the reason that the text is ambiguous.
    /// - Throws: The error of the model.
    func normalize(_ text: String, timeZone: TimeZone, now: Date) async throws -> AgentScheduleNormalization
}

/// The normalizer on the flash slot of the profile: the selection model of
/// the environment, as `find agents` and `searchTools` use it.
public struct ModelScheduleNormalizer: AgentScheduleNormalizing {
    /// The model.
    let model: any LanguageModel

    /// The instructions of each normalizer session.
    static let instructions = """
        You change one schedule text into one machine form. You never guess.
        - A schedule that repeats on days or times of the clock: a 5-field cron expression.
        - A schedule that repeats at a fixed step: every N minutes, every N hours, or every N days.
        - One time, for example 'in two hours' or 'tomorrow at 9 AM': the local date and time as \
        yyyy-MM-ddTHH:mm, counted from the current time.
        - When the text can mean two schedules, or misses a part that you need, give an empty \
        schedule and say why in ambiguity.
        """

    /// Makes a normalizer.
    ///
    /// - Parameter model: The flash model.
    public init(model: any LanguageModel) {
        self.model = model
    }

    /// Asks the model for one direct form of `text`.
    ///
    /// - Parameters:
    ///   - text: The English schedule text.
    ///   - timeZone: The time zone of the task.
    ///   - now: The current time.
    /// - Returns: The answer of the model.
    /// - Throws: The error of the model.
    public func normalize(_ text: String, timeZone: TimeZone, now: Date) async throws -> AgentScheduleNormalization {
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        return try await session.respond(
            to: Self.prompt(text, timeZone: timeZone, now: now), generating: AgentScheduleNormalization.self
        ).content
    }

    /// The prompt of one call: the current time, the time zone, and the
    /// text.
    ///
    /// - Parameters:
    ///   - text: The English schedule text.
    ///   - timeZone: The time zone of the task.
    ///   - now: The current time.
    /// - Returns: The prompt.
    static func prompt(_ text: String, timeZone: TimeZone, now: Date) -> String {
        let weekday = now.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.wide))
        return """
            Current time: \(AgentScheduleSpec.formatted(now, in: timeZone)) (\(weekday)), time zone \
            \(timeZone.identifier).
            <schedule>
            \(text)
            </schedule>
            """
    }
}

/// Reads a schedule text: a direct form at once, else English through the
/// normalizer. The answer of the normalizer must itself be a direct form,
/// thus a bad answer is refused and never used.
public struct AgentScheduleReader: Sendable {
    /// What ``read(_:timeZone:now:)`` gives.
    public enum Read: Sendable, Equatable {
        /// The schedule, and the English text that the normalizer read, or
        /// `nil` for a direct form.
        case parsed(AgentScheduleSpec, english: String?)

        /// The text cannot be a schedule, with the correction for the model.
        case refused(String)
    }

    /// The direct forms, for each correction.
    static let directForms = """
        Give a 5-field cron expression (for example 0 9 * * 1-5), one ISO date and time (for example \
        2026-11-10T09:00), or an interval (for example every 10 minutes).
        """

    /// The normalizer of English, or `nil` for none.
    let normalizer: (any AgentScheduleNormalizing)?

    /// Makes a reader.
    ///
    /// - Parameter normalizer: The normalizer of English, or `nil` to refuse
    ///   English.
    public init(normalizer: (any AgentScheduleNormalizing)?) {
        self.normalizer = normalizer
    }

    /// Reads `text`.
    ///
    /// - Parameters:
    ///   - text: The schedule text.
    ///   - timeZone: The time zone of the task.
    ///   - now: The current time.
    /// - Returns: The spec, or the correction.
    public func read(_ text: String, timeZone: TimeZone, now: Date) async -> Read {
        switch AgentScheduleSpec.parse(text, timeZone: timeZone, now: now) {
        case .parsed(let spec):
            return .parsed(spec, english: nil)
        case .refused(let reason):
            return .refused(reason)
        case .notDirect:
            return await normalize(text, timeZone: timeZone, now: now)
        }
    }

    /// Reads English `text` through the normalizer.
    ///
    /// - Parameters:
    ///   - text: The schedule text.
    ///   - timeZone: The time zone of the task.
    ///   - now: The current time.
    /// - Returns: The spec, or the correction.
    private func normalize(_ text: String, timeZone: TimeZone, now: Date) async -> Read {
        guard let normalizer else {
            return .refused("The schedule '\(text)' is not a form that can be read. \(Self.directForms)")
        }
        let answer: AgentScheduleNormalization
        do {
            answer = try await normalizer.normalize(text, timeZone: timeZone, now: now)
        } catch {
            return .refused("The schedule '\(text)' could not be read. \(Self.directForms)")
        }
        guard !AgentDefinitionRules.holdsText(answer.ambiguity) else {
            return .refused("The schedule '\(text)' is ambiguous: \(answer.ambiguity) \(Self.directForms)")
        }
        switch AgentScheduleSpec.parse(answer.schedule, timeZone: timeZone, now: now) {
        case .parsed(let spec):
            return .parsed(spec, english: text)
        case .refused(let reason):
            return .refused(reason)
        case .notDirect:
            return .refused("The schedule '\(text)' could not be read. \(Self.directForms)")
        }
    }
}
