import FoundationModelsRouter

/// Finds the answers to mail alone in the session events of one session.
///
/// The ids of an answer (``SessionAnswer/mailIds``) hold each mail that the
/// answer delivered: user-type mail and run mail. Thus the ids do not tell
/// if a caller message started the answer. The first submission of each
/// chain tells it: its cause is `.message` when the chain delivered
/// user-type mail, and `.mail` when the chain delivered run mail alone. A
/// continuation does not change the cause of its chain.
///
/// Give each event to ``answerToMailAlone(in:)`` in stream order. After an
/// event, ``isChainOfMailAlone`` tells the cause of the current chain, also
/// for its failure (``SessionEvent/answerFailed(_:)``).
struct MailAnswerFilter {
    /// `true` when the first submission of the current chain delivered run
    /// mail alone.
    private(set) var isChainOfMailAlone = false

    /// Reads one session event, and gives the answer when the event ends a
    /// chain that run mail alone started.
    ///
    /// - Parameter event: The next session event of the session.
    /// - Returns: The answer of a chain that run mail alone started, or
    ///   `nil` for each other event.
    mutating func answerToMailAlone(in event: SessionEvent) -> SessionAnswer? {
        switch event {
        case .submissionStarted(let start) where start.cause != .continuation:
            isChainOfMailAlone = start.cause == .mail
            return nil
        case .answered(let answer) where isChainOfMailAlone:
            return answer
        default:
            return nil
        }
    }

    /// Reads `outputs` until the first answer to mail alone.
    ///
    /// - Parameter outputs: The session outputs of one session, from before
    ///   its first message.
    /// - Returns: The first answer of a chain that run mail alone started,
    ///   or `nil` when the outputs end first.
    static func firstAnswerToMailAlone(in outputs: AsyncStream<SessionOutput>) async -> SessionAnswer? {
        var filter = MailAnswerFilter()
        for await output in outputs {
            if let answer = filter.answerToMailAlone(in: output.event) {
                return answer
            }
        }
        return nil
    }
}
