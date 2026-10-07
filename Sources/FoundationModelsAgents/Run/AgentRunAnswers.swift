import FoundationModels
import FoundationModelsRouter

/// The answers of the session of one run, as its session events tell them
/// (plan.md §8 steps 6 to 8).
///
/// An answer is the chain of submissions that answers the messages of the
/// session: the task prompt, or the final message of a run that this run
/// started. The run reads one session-event subscription, and this record
/// keeps what the run needs from it: whether an answer is open, the text of
/// the last answer, the text that the open answer streamed so far, and the
/// newest transcript entry that the events recorded.
struct AgentRunAnswers: Sendable, Equatable {
    /// `true` from a submission start to the end of its answer.
    private(set) var isAnswerOpen = false

    /// `true` after the first answer of the session.
    private(set) var hasAnswered = false

    /// The reply of the last answer, or an empty text before the first one.
    private(set) var lastReply = ""

    /// The text that the open answer streamed so far.
    private(set) var streamedText = ""

    /// The id of the newest transcript entry that a processed
    /// `entryRecorded` event named, or `nil` before the first one.
    internal private(set) var lastRecordedEntryID: String?

    /// The text so far of the run: the text that the open answer streamed,
    /// or the reply of the last answer when the open answer streamed none.
    var partial: String {
        streamedText.isEmpty ? lastReply : streamedText
    }

    /// Applies one session event.
    ///
    /// - Parameter event: The event.
    mutating func apply(_ event: SessionEvent) {
        if case .submissionStarted = event {
            isAnswerOpen = true
        }
        if case .textDelta(let fragment) = event {
            streamedText += fragment
        }
        if case .textReset = event {
            streamedText = ""
        }
        if case .answered(let answer) = event {
            close(reply: answer.reply)
        }
        if case .answerFailed = event {
            isAnswerOpen = false
        }
        if case .entryRecorded(let id, _) = event {
            lastRecordedEntryID = id
        }
    }

    /// Tells if an answer that the processed events ended answered a prompt
    /// of `transcript` that holds `text`.
    ///
    /// The transcript can be ahead of the processed events: the Router
    /// settles the transcript at the end of a submission, and the run reads
    /// the events of that submission later. Thus a prompt in the transcript
    /// is not proof of an answer. The Router sends `entryRecorded` for each
    /// entry of a submission after its `submissionStarted` and before the
    /// end of its answer. Thus a prompt before the newest entry that a
    /// processed `entryRecorded` named was answered when no answer is open.
    /// A prompt after that entry belongs to an answer whose events the run
    /// did not process yet.
    ///
    /// - Parameters:
    ///   - text: The text that the prompt holds, for example a final message.
    ///   - transcript: A transcript of the session.
    /// - Returns: `true` when no answer is open, and a prompt that holds
    ///   `text` comes before the newest recorded entry. `false` also when
    ///   `transcript` does not hold that entry, for example after a
    ///   compaction: the end of the next answer then checks again.
    internal func hasAnswered(promptHolding text: String, in transcript: Transcript) -> Bool {
        answeredPromptTexts(in: transcript).contains { $0.contains(text) }
    }

    /// Gives the text of each prompt of `transcript` that an answer that the
    /// processed events ended answered.
    ///
    /// The rule of ``hasAnswered(promptHolding:in:)`` decides which prompts
    /// are answered: each prompt before the newest entry that a processed
    /// `entryRecorded` named, when no answer is open.
    ///
    /// - Parameter transcript: A transcript of the session.
    /// - Returns: The text of each answered prompt, in transcript order. No
    ///   text while an answer is open, or when `transcript` does not hold the
    ///   newest recorded entry.
    internal func answeredPromptTexts(in transcript: Transcript) -> [String] {
        guard !isAnswerOpen,
            let lastRecordedEntryID,
            let end = transcript.firstIndex(where: { $0.id == lastRecordedEntryID })
        else {
            return []
        }
        return AgentRun.promptTexts(in: Transcript(entries: transcript[transcript.startIndex..<end]))
    }

    /// Ends the open answer with `reply`.
    ///
    /// - Parameter reply: The reply of the answer.
    private mutating func close(reply: String) {
        isAnswerOpen = false
        hasAnswered = true
        lastReply = reply
        streamedText = ""
    }
}

/// One thing that decides the end of a run, as the parts of the run tell it
/// to the task that drives the run (plan.md §8 steps 6 to 8).
enum AgentRunSignal: Sendable {
    /// The session of the run is idle: no run that it started is open, each
    /// final message of those runs was delivered and answered, and no
    /// message waits. The text is the reply of the last answer. The count is
    /// the count of messages from the caller that the run accepted before
    /// the idle check (``AgentRun/deliver(_:)``).
    case idle(String, acceptedMessages: Int)

    /// The count of passes went above the `maxTurns` limit, and the open
    /// answer ended. The text is the text so far.
    case limitHit(partial: String)

    /// A caller cancelled the run.
    case cancelRequested

    /// The answer of the task prompt failed with this error.
    case taskAnswerFailed(any Error)

    /// An answer to a final message failed.
    case mailAnswerFailed(AnswerFailure.Reason)

    /// The Router held the final messages, and started no answer for them.
    /// The text is the description of the hold.
    case mailDeliveryPaused(String)

    /// The session-event subscription finished.
    case sessionClosed
}
