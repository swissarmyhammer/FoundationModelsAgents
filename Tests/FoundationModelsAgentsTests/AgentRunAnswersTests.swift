import FoundationModels
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins the rule that tells if an answer answered a prompt (plan.md §8 steps
/// 6 to 8): the rule reads the session events that the run processed, not
/// only the transcript.
///
/// The transcript of a session can be ahead of the events that a run
/// processed: the Router settles the transcript at the end of a submission,
/// and the run reads the events of that submission later. Each test records
/// the events and the transcript of one real session with two answers. It
/// then applies only a part of the events, and reads the full transcript,
/// thus the transcript is ahead of the events with no timing.
@Suite("Agent run answers")
struct AgentRunAnswersTests {
    /// The events and the transcript of one session with two answers.
    private struct Recording {
        /// The session events, in the order of the subscription.
        let events: [SessionEvent]

        /// The transcript of the session after the two answers.
        let transcript: Transcript

        /// The events up to and with the end of the first answer.
        var firstAnswerEvents: [SessionEvent] {
            Array(events.prefix(through: answerEnds[0]))
        }

        /// The events up to the end of the second answer, without that end:
        /// the second answer is open.
        var openSecondAnswerEvents: [SessionEvent] {
            Array(events.prefix(upTo: answerEnds[1]))
        }

        /// The positions of the `answered` events in ``events``.
        private var answerEnds: [Int] {
            events.indices.filter { index in
                if case .answered = events[index] { true } else { false }
            }
        }
    }

    /// The key of the play of the session.
    private static let playKey = "answers-rule-key"

    /// The task prompt of the session.
    private static let taskPrompt = "answers-rule-key: start one agent"

    /// The reply of the answer of the task prompt.
    private static let taskReply = "I started one agent."

    /// The second message: it holds the final message of a run, as mail does.
    private static let finalMessage = "[agents] The agent finished: the part is done."

    /// The reply of the answer of the second message.
    private static let mailReply = "The part is done, thus the task is done."

    /// The count of answers of the recorded session.
    private static let answerCount = 2

    /// Runs one real session with two answers on the scripted model, and
    /// records its session events and its transcript.
    ///
    /// - Returns: The recording.
    /// - Throws: The error of the harness or of an answer.
    private static func recordTwoAnswers() async throws -> Recording {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: playKey, steps: [.finalText(taskReply), .finalText(mailReply)])
            ]))
        defer { try? harness.delete() }
        let session = harness.profile.standard.makeSession(instructions: playKey, tools: [])
        let stream = await session.streamSessionEvents()

        #expect(try await session.respond(to: taskPrompt) == taskReply)
        #expect(try await session.respond(to: finalMessage) == mailReply)
        let transcript = await session.transcript
        var events: [SessionEvent] = []
        var answers = 0
        for await event in stream {
            events.append(event)
            if case .answered = event {
                answers += 1
            }
            if answers == answerCount {
                break
            }
        }
        await session.close()
        return Recording(events: events, transcript: transcript)
    }

    /// Gives a record that applied `events` in order.
    ///
    /// - Parameter events: The session events.
    /// - Returns: The record.
    private static func answers(applying events: [SessionEvent]) -> AgentRunAnswers {
        events.reduce(into: AgentRunAnswers()) { answers, event in answers.apply(event) }
    }

    @Test(
        "a prompt that holds the final message is not answered when the events of its answer are not processed",
        .timeLimit(.minutes(1)))
    func promptAheadOfEventsIsNotAnswered() async throws {
        let recording = try await Self.recordTwoAnswers()
        let answers = Self.answers(applying: recording.firstAnswerEvents)

        #expect(AgentRun.promptTexts(in: recording.transcript).last == Self.finalMessage)
        #expect(!answers.isAnswerOpen)
        #expect(answers.lastReply == Self.taskReply)
        #expect(!answers.hasAnswered(promptHolding: Self.finalMessage, in: recording.transcript))
    }

    @Test(
        "a prompt that holds the final message is answered when the end of its answer is processed",
        .timeLimit(.minutes(1)))
    func promptBeforeProcessedEndIsAnswered() async throws {
        let recording = try await Self.recordTwoAnswers()
        let answers = Self.answers(applying: recording.events)

        #expect(answers.lastReply == Self.mailReply)
        #expect(answers.hasAnswered(promptHolding: Self.finalMessage, in: recording.transcript))
    }

    @Test(
        "an open answer has not answered its prompt yet, also when its response is recorded",
        .timeLimit(.minutes(1)))
    func openAnswerHasNotAnsweredPrompt() async throws {
        let recording = try await Self.recordTwoAnswers()
        let answers = Self.answers(applying: recording.openSecondAnswerEvents)

        #expect(answers.isAnswerOpen)
        #expect(!answers.hasAnswered(promptHolding: Self.finalMessage, in: recording.transcript))
    }

    @Test(
        "the answered prompt texts are the prompts that the processed answers answered, and none while an answer is open",
        .timeLimit(.minutes(1)))
    func answeredPromptTextsFollowTheProcessedEvents() async throws {
        let recording = try await Self.recordTwoAnswers()
        let first = Self.answers(applying: recording.firstAnswerEvents)
        let open = Self.answers(applying: recording.openSecondAnswerEvents)
        let both = Self.answers(applying: recording.events)

        #expect(first.answeredPromptTexts(in: recording.transcript) == [Self.taskPrompt])
        #expect(open.answeredPromptTexts(in: recording.transcript).isEmpty)
        #expect(both.answeredPromptTexts(in: recording.transcript) == [Self.taskPrompt, Self.finalMessage])
    }

    @Test(
        "a transcript without the newest recorded entry, for example after a compaction, answers no prompt",
        .timeLimit(.minutes(1)))
    func transcriptWithoutRecordedEntryAnswersNoPrompt() async throws {
        let recording = try await Self.recordTwoAnswers()
        let answers = Self.answers(applying: recording.events)
        let withoutResponses = Transcript(
            entries: recording.transcript.filter { entry in
                if case .response = entry { false } else { true }
            })

        #expect(AgentRun.promptTexts(in: withoutResponses).last == Self.finalMessage)
        #expect(!answers.hasAnswered(promptHolding: Self.finalMessage, in: withoutResponses))
    }
}
