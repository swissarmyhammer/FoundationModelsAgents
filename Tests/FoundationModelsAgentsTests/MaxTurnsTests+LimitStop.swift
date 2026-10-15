@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

extension MaxTurnsTests {
    /// Pins the time of the stop after the count of passes went above the
    /// limit (``AgentRunLimitStop``).
    ///
    /// Each test gives the counter and the rule the same events in the same
    /// fixed order as the follower of a run: first the counter applies the
    /// event, then the rule gets the result, then the rule gets the signal of
    /// the event. The events are synthetic, thus the tests need no session
    /// and no timing.
    @Suite("maxTurns limit stop")
    struct LimitStop {
        /// The `maxTurns` limit of the counter.
        private static let turnLimit = 2

        /// The reply of the answer that goes above the limit.
        private static let reply = "The part is done."

        /// Gives a generation call event.
        ///
        /// - Parameter kind: What the call left in the transcript.
        /// - Returns: The event.
        private static func generationCall(_ kind: GenerationCallEntryKind) -> SessionEvent {
            .generationCall(
                GenerationCallUsage(
                    tokensIn: 1, tokensOut: 1, finishReason: .completed, entryKind: kind, contextFill: 0))
        }

        /// Gives each event to `turns` and then to `rule`, as the follower of
        /// a run does.
        ///
        /// - Parameters:
        ///   - events: The events, in order.
        ///   - turns: The counter.
        ///   - rule: The rule.
        /// - Returns: The action of the rule after each event, in order.
        private static func actions(
            after events: [SessionEvent], turns: AgentRunTurns, rule: inout AgentRunLimitStop
        ) -> [AgentRunLimitStop.Action] {
            events.map { rule.action(after: $0, wentAboveLimit: turns.apply($0)) }
        }

        @Test("a text call above the limit stops the session at the limitHit signal of its answer, not at the call")
        func textCallStopsAtAnswerEnd() {
            let turns = AgentRunTurns(limit: Self.turnLimit)
            var rule = AgentRunLimitStop()
            turns.startSubmission()

            let callActions = Self.actions(
                after: [Self.generationCall(.toolCall), Self.generationCall(.toolCall), Self.generationCall(.text)],
                turns: turns, rule: &rule)
            let signalAction = rule.action(at: .limitHit(partial: Self.reply))

            #expect(turns.isLimitHit)
            #expect(callActions == [.none, .none, .none])
            #expect(signalAction == .stop)
        }

        @Test("a tool call above the limit stops the session at once, and its limitHit signal stops nothing more")
        func toolCallStopsAtOnce() {
            let turns = AgentRunTurns(limit: Self.turnLimit)
            var rule = AgentRunLimitStop()
            turns.startSubmission()

            let callActions = Self.actions(
                after: [
                    Self.generationCall(.toolCall), Self.generationCall(.toolCall), Self.generationCall(.toolCall),
                ],
                turns: turns, rule: &rule)
            let signalAction = rule.action(at: .limitHit(partial: Self.reply))

            #expect(callActions == [.none, .none, .stop])
            #expect(signalAction == .none)
        }

        @Test("after a text call above the limit, only the limitHit signal stops the session, and only one time")
        func onlyLimitHitStopsOneTime() {
            let turns = AgentRunTurns(limit: Self.turnLimit)
            var rule = AgentRunLimitStop()
            turns.startSubmission()
            _ = Self.actions(
                after: [Self.generationCall(.toolCall), Self.generationCall(.toolCall), Self.generationCall(.text)],
                turns: turns, rule: &rule)

            let idleAction = rule.action(at: .idle(Self.reply, acceptedMessages: 0))
            let firstLimitAction = rule.action(at: .limitHit(partial: Self.reply))
            let secondLimitAction = rule.action(at: .limitHit(partial: Self.reply))

            #expect(idleAction == .none)
            #expect(firstLimitAction == .stop)
            #expect(secondLimitAction == .none)
        }

        @Test("a text call at or below the limit stops nothing")
        func textCallBelowLimitStopsNothing() {
            let turns = AgentRunTurns(limit: Self.turnLimit)
            var rule = AgentRunLimitStop()
            turns.startSubmission()

            let callActions = Self.actions(
                after: [Self.generationCall(.toolCall), Self.generationCall(.text)], turns: turns, rule: &rule)
            let signalAction = rule.action(at: .idle(Self.reply, acceptedMessages: 0))

            #expect(!turns.isLimitHit)
            #expect(callActions == [.none, .none])
            #expect(signalAction == .none)
        }
    }
}
