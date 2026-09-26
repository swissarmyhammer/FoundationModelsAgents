import FoundationModelsRouter

/// The answers of the session of one run, as its session events tell them
/// (plan.md §8 steps 6 to 8).
///
/// An answer is the chain of submissions that answers the messages of the
/// session: the task prompt, or the final message of a run that this run
/// started. The run reads one session-event subscription, and this record
/// keeps what the run needs from it: whether an answer is open, the text of
/// the last answer, and the text that the open answer streamed so far.
struct AgentRunAnswers: Sendable, Equatable {
    /// `true` from a submission start to the end of its answer.
    private(set) var isAnswerOpen = false

    /// `true` after the first answer of the session.
    private(set) var hasAnswered = false

    /// The reply of the last answer, or an empty text before the first one.
    private(set) var lastReply = ""

    /// The text that the open answer streamed so far.
    private(set) var streamedText = ""

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
    /// message waits. The text is the reply of the last answer.
    case idle(String)

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
