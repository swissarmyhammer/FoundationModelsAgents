import Foundation
@testable import FoundationModelsAgents
import Synchronization
import Testing

/// Pins the read of a schedule text: a direct form needs no model, and
/// English goes to the normalizer, whose answer must itself be a direct form.
@Suite("Agent schedule reader")
struct AgentScheduleReaderTests {
    /// The time zone of the tests.
    private static let zone = TimeZone(identifier: "America/New_York")!

    /// The current time of the tests: Monday 2026-11-09 08:30 in ``zone``.
    private static let now = ISO8601DateFormatter().date(from: "2026-11-09T08:30:00-05:00")!

    /// A normalizer that gives one fixed answer and records each text.
    private final class StubNormalizer: AgentScheduleNormalizing, Sendable {
        /// The answer of each call.
        let answer: AgentScheduleNormalization

        /// The texts of the calls.
        let texts = Mutex<[String]>([])

        /// Makes a stub.
        ///
        /// - Parameter answer: The answer of each call.
        init(_ answer: AgentScheduleNormalization) {
            self.answer = answer
        }

        func normalize(_ text: String, timeZone: TimeZone, now: Date) async throws -> AgentScheduleNormalization {
            texts.withLock { $0.append(text) }
            return answer
        }
    }

    @Test("a direct form never calls the normalizer")
    func directFormNeedsNoModel() async {
        let normalizer = StubNormalizer(AgentScheduleNormalization(schedule: "0 1 * * *"))
        let reader = AgentScheduleReader(normalizer: normalizer)

        let read = await reader.read("*/5 * * * *", timeZone: Self.zone, now: Self.now)

        guard case .parsed(let spec, let english) = read else {
            Issue.record("not parsed: \(read)")
            return
        }
        #expect(spec.normalized(timeZone: Self.zone) == "*/5 * * * *")
        #expect(english == nil)
        #expect(normalizer.texts.withLock { $0 }.isEmpty)
    }

    @Test("English goes to the normalizer, and its answer is parsed")
    func englishIsNormalized() async {
        let normalizer = StubNormalizer(AgentScheduleNormalization(schedule: "0 9 * * 1-5"))
        let reader = AgentScheduleReader(normalizer: normalizer)

        let read = await reader.read("weekdays at 9", timeZone: Self.zone, now: Self.now)

        guard case .parsed(let spec, let english) = read else {
            Issue.record("not parsed: \(read)")
            return
        }
        #expect(spec.normalized(timeZone: Self.zone) == "0 9 * * 1-5")
        #expect(english == "weekdays at 9")
        #expect(normalizer.texts.withLock { $0 } == ["weekdays at 9"])
    }

    @Test("an ambiguous text is refused with the reason of the normalizer")
    func ambiguousIsRefused() async {
        let reader = AgentScheduleReader(
            normalizer: StubNormalizer(
                AgentScheduleNormalization(schedule: "", ambiguity: "'at 9' can be 9 AM or 9 PM")))

        let read = await reader.read("Mondays at 9", timeZone: Self.zone, now: Self.now)

        guard case .refused(let reason) = read else {
            Issue.record("not refused: \(read)")
            return
        }
        #expect(reason.contains("9 AM or 9 PM"))
        #expect(reason.contains("cron"))
    }

    @Test("a normalizer answer that is not a direct form is refused, never guessed")
    func badAnswerIsRefused() async {
        let reader = AgentScheduleReader(
            normalizer: StubNormalizer(AgentScheduleNormalization(schedule: "every weekday morning")))

        guard case .refused = await reader.read("weekday mornings", timeZone: Self.zone, now: Self.now) else {
            Issue.record("a non-direct answer was used")
            return
        }
    }

    @Test("a normalized schedule faster than a minute is refused")
    func fastAnswerIsRefused() async {
        let reader = AgentScheduleReader(normalizer: StubNormalizer(AgentScheduleNormalization(schedule: "every 10 seconds")))

        guard case .refused(let reason) = await reader.read("constantly", timeZone: Self.zone, now: Self.now) else {
            Issue.record("a fast answer was used")
            return
        }
        #expect(reason.contains("1 minute"))
    }

    @Test("with no normalizer, English is refused with the direct forms")
    func noNormalizer() async {
        let reader = AgentScheduleReader(normalizer: nil)

        guard case .refused(let reason) = await reader.read("weekdays at 9", timeZone: Self.zone, now: Self.now) else {
            Issue.record("English was read with no normalizer")
            return
        }
        #expect(reason.contains("cron"))
        #expect(reason.contains("every 10 minutes"))
    }

    @Test("the model normalizer reads the guided answer of the flash model")
    func modelNormalizer() async throws {
        let calls = SelectionProbeCalls()
        let normalizer = ModelScheduleNormalizer(
            model: SelectionProbeModel(calls: calls, answer: #"{"schedule": "0 9 * * 1-5", "ambiguity": ""}"#))

        let answer = try await normalizer.normalize("weekdays at 9", timeZone: Self.zone, now: Self.now)

        #expect(answer == AgentScheduleNormalization(schedule: "0 9 * * 1-5", ambiguity: ""))
        #expect(calls.count == 1)
    }

    @Test("a failed model call is refused, not thrown")
    func modelFailureIsRefused() async {
        let reader = AgentScheduleReader(
            normalizer: ModelScheduleNormalizer(model: SelectionProbeModel(calls: SelectionProbeCalls())))

        guard case .refused = await reader.read("weekdays at 9", timeZone: Self.zone, now: Self.now) else {
            Issue.record("a failed model call was not refused")
            return
        }
    }
}
