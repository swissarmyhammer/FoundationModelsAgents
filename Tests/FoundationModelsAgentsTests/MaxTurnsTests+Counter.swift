import FoundationModels
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Synchronization
import Testing

extension MaxTurnsTests {
    /// Pins the one pass counter of a run (plan.md §5): the background count
    /// of the session events, the exact count from the transcript after each
    /// turn, and the end state when the count goes above the limit.
    ///
    /// The tests give the counter synthetic events, transcripts, and
    /// dispatch results, thus they need no session.
    @Suite("maxTurns counter")
    struct Counter {
        /// The `maxTurns` limit of the counters with a limit.
        private static let turnLimit = 2

        /// The count of `.toolCalls` entries in the tests of one tool pass.
        private static let oneToolPass = 1

        /// The count of `.response` entries of a turn that retried after an
        /// overflow.
        private static let retryAnswers = 2

        /// The count of pass events above the limit in the follower test.
        private static let passesAboveLimit = 1

        /// The text of the last complete turn before a delivery turn.
        private static let lastText = "I started the helper."

        /// The text that a delivery turn gives.
        private static let deliveredText = "The part is done."

        /// The arguments of the tool call of each `.toolCalls` entry.
        private static let callArguments = #"{"op": "list agents"}"#

        /// Gives a transcript with `toolPasses` tool-calls entries, then
        /// `answers` response entries.
        ///
        /// - Parameters:
        ///   - toolPasses: The count of `.toolCalls` entries.
        ///   - answers: The count of `.response` entries.
        /// - Returns: The transcript.
        /// - Throws: The error of the arguments JSON.
        private static func transcript(toolPasses: Int, answers: Int) throws -> Transcript {
            let call = Transcript.ToolCall(
                id: "call", toolName: ToolVocabulary.agentsToolName,
                arguments: try GeneratedContent(json: callArguments))
            let calls = Transcript.Entry.toolCalls(Transcript.ToolCalls(id: "calls", [call]))
            let answer = Transcript.Entry.response(
                Transcript.Response(segments: [.text(Transcript.TextSegment(content: deliveredText))]))
            return Transcript(
                entries: Array(repeating: calls, count: toolPasses) + Array(repeating: answer, count: answers))
        }

        /// Gives the event of a recorded entry.
        ///
        /// - Parameter kind: The kind of the entry.
        /// - Returns: The event.
        private static func entry(_ kind: RecordedEntryKind) -> SessionEvent {
            .entryRecorded(id: "entry", kind: kind)
        }

        /// Gives a counter with the limit that has seen one pass more than
        /// the limit.
        ///
        /// - Returns: The counter. Its limit flag is set.
        private static func counterAboveLimit() -> AgentRunTurns {
            let turns = AgentRunTurns(limit: turnLimit)
            for event in [entry(.toolCalls), entry(.toolCalls), entry(.response)] {
                _ = turns.add(event)
            }
            return turns
        }

        @Test("a delivery turn with no response entry returns, and the transcript gives its count",
            .timeLimit(.minutes(1)))
        func deliveryWithNoResponseReturns() async throws {
            let turns = AgentRunTurns(limit: nil)
            let transcript = try Self.transcript(toolPasses: Self.oneToolPass, answers: 0)

            let delivered = try await turns.deliver(
                lastText: Self.lastText, dispatch: { Self.deliveredText }, transcript: { transcript })

            #expect(delivered == Self.deliveredText)
            #expect(turns.count == Self.oneToolPass)
        }

        @Test("a delivery turn that retried with two response entries counts both", .timeLimit(.minutes(1)))
        func retryCountsBothAnswers() async throws {
            let turns = AgentRunTurns(limit: nil)
            let transcript = try Self.transcript(toolPasses: 0, answers: Self.retryAnswers)

            _ = try await turns.deliver(
                lastText: Self.lastText, dispatch: { Self.deliveredText }, transcript: { transcript })

            #expect(turns.count == Self.retryAnswers)
        }

        @Test("the count is exact when a delivery turn returns, and a late event of that turn does not count again",
            .timeLimit(.minutes(1)))
        func countIsExactAfterDelivery() async throws {
            let turns = AgentRunTurns(limit: nil)
            let transcript = try Self.transcript(toolPasses: Self.oneToolPass, answers: Self.retryAnswers)
            _ = turns.add(Self.entry(.toolCalls))

            _ = try await turns.deliver(
                lastText: Self.lastText, dispatch: { Self.deliveredText }, transcript: { transcript })
            let exact = turns.count
            _ = turns.add(Self.entry(.response))
            _ = turns.add(Self.entry(.response))

            #expect(exact == Self.oneToolPass + Self.retryAnswers)
            #expect(turns.count == exact)
        }

        @Test("the follower counts the pass entries and cancels the turn one time above the limit",
            .timeLimit(.minutes(1)))
        func followerCancelsOnceAboveLimit() async {
            let turns = AgentRunTurns(limit: Self.turnLimit)
            let (events, continuation) = AsyncStream<SessionEvent>.makeStream()
            let entries = [
                Self.entry(.toolCalls), Self.entry(.reasoning), Self.entry(.toolCalls), Self.entry(.response)
            ]
            for event in entries {
                continuation.yield(event)
            }
            continuation.finish()
            let cancels = Mutex(0)

            await turns.follow(events, onEvent: { _ in }, onLimitHit: { cancels.withLock { $0 += 1 } })

            #expect(cancels.withLock { $0 } == 1)
            #expect(turns.isLimitHit)
            #expect(turns.count == Self.turnLimit + Self.passesAboveLimit)
        }

        @Test("after the limit cancel, a cancelled delivery turn ends as hitMaxTurns with the last complete text",
            .timeLimit(.minutes(1)))
        func deliveryCancelEndsAsHitMaxTurns() async {
            let turns = Self.counterAboveLimit()

            await #expect(throws: AgentRunFailure.hitMaxTurns(partial: Self.lastText)) {
                try await turns.deliver(
                    lastText: Self.lastText, dispatch: { throw CancellationError() }, transcript: { Transcript() })
            }
        }

        @Test("after the limit cancel, a cancelled task turn ends as hitMaxTurns with the text so far")
        func taskTurnCancelEndsAsHitMaxTurns() {
            let below = AgentRunTurns(limit: Self.turnLimit)
            let above = Self.counterAboveLimit()

            #expect(below.failure(for: CancellationError(), partial: Self.lastText) is CancellationError)
            #expect(
                above.failure(for: CancellationError(), partial: Self.lastText) as? AgentRunFailure
                    == .hitMaxTurns(partial: Self.lastText))
        }
    }
}
