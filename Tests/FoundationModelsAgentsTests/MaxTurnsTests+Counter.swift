import Foundation
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing
import ULID

extension MaxTurnsTests {
    /// Pins the one pass counter of a run: the live count from the generation
    /// calls and the tool opens of the submission in operation, the
    /// correction from the recorded entries at the end of each
    /// submission, and the one limit signal.
    ///
    /// The tests give the counter synthetic events, thus they need no
    /// session. The Router makes the submission ids, thus the tests start
    /// and end a submission with the counter's own calls.
    @Suite("maxTurns counter")
    struct Counter {
        /// The `maxTurns` limit of the counters with a limit.
        private static let turnLimit = 2

        /// The count of passes of a submission with one tool pass and one
        /// answer.
        private static let toolPassAndAnswer = 2

        /// The count of pass entries of a submission that retried after an
        /// overflow: two answers.
        private static let retryAnswers = 2

        /// The count of tool calls in one pass.
        private static let callsInOnePass = 3

        /// The count of submissions of the test of several submissions.
        private static let submissionCount = 3

        /// Gives a generation call event.
        ///
        /// - Parameter kind: What the call left in the transcript.
        /// - Returns: The event.
        private static func generationCall(_ kind: GenerationCallEntryKind) -> SessionEvent {
            .generationCall(
                GenerationCallUsage(
                    tokensIn: 1, tokensOut: 1, finishReason: .completed, entryKind: kind, contextFill: 0))
        }

        /// Gives the open record of one tool call.
        ///
        /// - Returns: The event.
        private static func toolOpen() -> SessionEvent {
            .toolInvocation(
                ToolInvocationRecord(
                    tool: ToolVocabulary.agentsToolName, op: "list agents", correlationID: ULID().ulidString,
                    sessionID: ULID(), openedAt: Date()))
        }

        /// Gives the event of a recorded entry.
        ///
        /// - Parameter kind: The kind of the entry.
        /// - Returns: The event.
        private static func entry(_ kind: RecordedEntryKind) -> SessionEvent {
            .entryRecorded(id: "entry", kind: kind)
        }

        /// Gives each event to `turns`.
        ///
        /// - Parameters:
        ///   - events: The events, in order.
        ///   - turns: The counter.
        /// - Returns: The results of ``AgentRunTurns/apply(_:)``, in order.
        private static func apply(_ events: [SessionEvent], to turns: AgentRunTurns) -> [Bool] {
            events.map(turns.apply)
        }

        @Test("each generation call counts one live pass before the submission ends")
        func generationCallsCountLive() {
            let turns = AgentRunTurns(limit: nil)
            turns.startSubmission()

            _ = Self.apply([Self.generationCall(.toolCall), Self.toolOpen(), Self.generationCall(.text)], to: turns)

            #expect(turns.count == Self.toolPassAndAnswer)
        }

        @Test("one pass that opens three tools counts one")
        func threeToolOpensInOnePassCountOne() {
            let turns = AgentRunTurns(limit: nil)
            turns.startSubmission()
            let opens = [SessionEvent](repeating: Self.toolOpen(), count: Self.callsInOnePass)

            _ = Self.apply([Self.generationCall(.toolCall)] + opens, to: turns)

            #expect(turns.count == 1)
        }

        @Test("tool opens that come before the generation call of their pass count no second pass")
        func toolOpensBeforeGenerationCallCountOnePass() {
            let turns = AgentRunTurns(limit: nil)
            turns.startSubmission()

            _ = Self.apply(
                [Self.toolOpen(), Self.toolOpen(), Self.generationCall(.toolCall), Self.toolOpen(),
                 Self.generationCall(.text)],
                to: turns)

            #expect(turns.count == Self.toolPassAndAnswer)
        }

        @Test("with no generation call, the first tool open of a submission counts one pass")
        func toolOpenCountsWithNoGenerationCall() {
            let turns = AgentRunTurns(limit: nil)
            turns.startSubmission()

            _ = Self.apply([Self.toolOpen(), Self.toolOpen()], to: turns)

            #expect(turns.count == 1)
        }

        @Test("at the end of a submission, its recorded pass entries replace its live count")
        func recordedEntriesCorrectTheCount() {
            let turns = AgentRunTurns(limit: nil)
            turns.startSubmission()
            _ = Self.apply([Self.generationCall(.text), Self.entry(.response), Self.entry(.response)], to: turns)

            _ = turns.endSubmission()

            #expect(turns.count == Self.retryAnswers)
        }

        @Test("a reasoning entry is not a pass")
        func reasoningEntryIsNotAPass() {
            let turns = AgentRunTurns(limit: nil)
            turns.startSubmission()
            _ = Self.apply([Self.entry(.reasoning), Self.entry(.response)], to: turns)

            _ = turns.endSubmission()

            #expect(turns.count == 1)
        }

        @Test("the passes of each submission add to one count")
        func submissionsAddToOneCount() {
            let turns = AgentRunTurns(limit: nil)

            for _ in 0..<Self.submissionCount {
                turns.startSubmission()
                _ = Self.apply([Self.generationCall(.text), Self.entry(.response)], to: turns)
                _ = turns.endSubmission()
            }

            #expect(turns.count == Self.submissionCount)
        }

        @Test("the count goes above the limit one time, and the flag stays")
        func limitSignalsOneTime() {
            let turns = AgentRunTurns(limit: Self.turnLimit)
            turns.startSubmission()
            let calls = [SessionEvent](repeating: Self.generationCall(.toolCall), count: Self.turnLimit + 1)

            let signals = Self.apply(calls + [Self.generationCall(.text)], to: turns)

            #expect(signals.count(where: \.self) == 1)
            #expect(signals.last == false)
            #expect(turns.isLimitHit)
        }

        @Test("recorded entries above the live count can go above the limit")
        func recordedEntriesCanGoAboveLimit() {
            let turns = AgentRunTurns(limit: Self.turnLimit)
            turns.startSubmission()
            let entries = [SessionEvent](repeating: Self.entry(.toolCalls), count: Self.turnLimit)

            let signals = Self.apply([Self.generationCall(.text)] + entries + [Self.entry(.response)], to: turns)

            #expect(signals == [false, false, false, true])
            #expect(turns.count == Self.turnLimit + 1)
        }
    }
}
