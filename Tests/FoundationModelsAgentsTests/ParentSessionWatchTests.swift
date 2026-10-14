import Foundation
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing
import ULID

/// Pins the id rule of the watch of a parent session: a mail of the call of
/// a child has a terminal event only when an `answered`, an `answerFailed`,
/// a `cancelled`, or a `lost` event names its id, and a tool call is closed
/// only when its close record came.
///
/// Each test gives the watch built `SessionOutput` values in a fixed order.
/// The Router can send `mailDelivered` and the terminal event of a mail
/// before or after the output of the run event that the mail holds. The
/// tests give each order, and the result does not change.
@Suite("Parent session watch")
struct ParentSessionWatchTests {
    /// The completion token of the `start agent` call of the child.
    private static let token = "watch-child-token"

    /// The completion token of a synchronous tool call that is not a child.
    private static let otherToken = "watch-other-token"

    /// The session of the watch.
    private static let sessionID = ULID()

    /// The time of each invocation record.
    private static let instant = Date(timeIntervalSince1970: 0)

    /// A message of the child, as the Router sends it in a `runMessage`
    /// event.
    private static let message = OperationEvent(
        tool: ToolVocabulary.agentsToolName, op: StartAgent.opString, correlationID: token, kind: .message,
        detail: "watch-message: half of the files are done")

    /// The terminal of the child, as the Router sends it in a `runSettled`
    /// event.
    private static let terminal = OperationEvent(
        tool: ToolVocabulary.agentsToolName, op: StartAgent.opString, correlationID: token, kind: .completed,
        detail: "watch-terminal: the files are done")

    /// The terminal of a synchronous tool call that posted progress, as the
    /// Router sends it in a `runSettled` event.
    private static let otherTerminal = OperationEvent(
        tool: "Read", op: "Read", correlationID: otherToken, kind: .completed, detail: "watch-other: the file is read")

    /// The open invocation record of the call of the child.
    private static let openRecord = ToolInvocationRecord(
        tool: ToolVocabulary.agentsToolName, op: StartAgent.opString, correlationID: token, sessionID: sessionID,
        openedAt: instant)

    /// The close invocation record of the call of the child.
    private static let closeRecord = openRecord.closed(at: instant)

    /// Gives the output of a run event that the mail `id` holds.
    ///
    /// - Parameters:
    ///   - event: The run event.
    ///   - id: The id of the run mail.
    /// - Returns: The output, with the origin `.mail([id])`.
    private static func output(_ event: SessionEvent, inMail id: MailID) -> SessionOutput {
        SessionOutput(origin: .mail([id]), event: event)
    }

    /// Gives the output of the answer of the mail `ids`.
    ///
    /// - Parameter ids: The mail ids of the answer.
    /// - Returns: The `answered` output.
    private static func answered(_ ids: [MailID]) -> SessionOutput {
        SessionOutput(
            origin: .mail(Set(ids)),
            event: .answered(
                SessionAnswer(
                    reply: "watch-reply", mailIds: ids, usage: nil, compactions: [], toolCalls: [],
                    toolInvocations: [])))
    }

    /// Gives a watch that observed `outputs` in order.
    ///
    /// - Parameter outputs: The outputs.
    /// - Returns: The watch.
    private static func watch(observing outputs: [SessionOutput]) -> ParentSessionWatch {
        let watch = ParentSessionWatch()
        for output in outputs {
            watch.observe(output)
        }
        return watch
    }

    /// Tells if each mail of the call of the child has a terminal event.
    ///
    /// - Parameter watch: The watch.
    /// - Returns: The answer of the watch for the call ``token``.
    private static func isEachChildMailEnded(in watch: ParentSessionWatch) -> Bool {
        watch.hasTerminal(forEachMailOfCalls: [token], and: [])
    }

    @Test("a child message whose mail is delivered before its runMessage output has a terminal only after its answer")
    func deliveryBeforeRunMessage() {
        let id = MailID()
        let delivered = SessionOutput(origin: .mail([id]), event: .mailDelivered(id))
        let runMessage = Self.output(.runMessage(Self.message), inMail: id)

        let open = Self.watch(observing: [delivered, runMessage])
        let ended = Self.watch(observing: [delivered, runMessage, Self.answered([id])])

        #expect(!Self.isEachChildMailEnded(in: open))
        #expect(Self.isEachChildMailEnded(in: ended))
    }

    @Test("a child message whose runMessage output comes before its delivery has a terminal only after its answer")
    func runMessageBeforeDelivery() {
        let id = MailID()
        let delivered = SessionOutput(origin: .mail([id]), event: .mailDelivered(id))
        let runMessage = Self.output(.runMessage(Self.message), inMail: id)

        let open = Self.watch(observing: [runMessage, delivered])
        let ended = Self.watch(observing: [runMessage, delivered, Self.answered([id])])

        #expect(!Self.isEachChildMailEnded(in: open))
        #expect(Self.isEachChildMailEnded(in: ended))
    }

    @Test("an answer that ends before the runMessage output of its mail still counts as the terminal of that mail")
    func answerBeforeRunMessage() {
        let id = MailID()
        let watch = Self.watch(
            observing: [Self.answered([id]), Self.output(.runMessage(Self.message), inMail: id)])

        #expect(Self.isEachChildMailEnded(in: watch))
    }

    @Test("a child message and the final message in one answer: one answer ends both mails")
    func messageAndFinalMessageInOneAnswer() {
        let messageID = MailID()
        let finalID = MailID()
        let runEvents = [
            Self.output(.runMessage(Self.message), inMail: messageID),
            Self.output(.runSettled(Self.terminal), inMail: finalID)
        ]

        let open = Self.watch(observing: runEvents)
        let ended = Self.watch(observing: runEvents + [Self.answered([messageID, finalID])])

        #expect(!Self.isEachChildMailEnded(in: open))
        #expect(Self.isEachChildMailEnded(in: ended))
    }

    @Test("a child message and the final message in two answers: the first answer does not end the final message")
    func messageAndFinalMessageInTwoAnswers() {
        let messageID = MailID()
        let finalID = MailID()
        let runEvents = [
            Self.output(.runMessage(Self.message), inMail: messageID),
            Self.output(.runSettled(Self.terminal), inMail: finalID)
        ]

        let first = Self.watch(observing: runEvents + [Self.answered([messageID])])
        let both = Self.watch(observing: runEvents + [Self.answered([messageID]), Self.answered([finalID])])

        #expect(!Self.isEachChildMailEnded(in: first))
        #expect(Self.isEachChildMailEnded(in: both))
    }

    @Test("a child mail that cancelAll() cancelled has a terminal: the cancelled event")
    func cancelledChildMailHasATerminal() {
        let id = MailID()
        let watch = Self.watch(
            observing: [
                Self.output(.runMessage(Self.message), inMail: id),
                SessionOutput(origin: .system, event: .cancelled(id))
            ])

        #expect(Self.isEachChildMailEnded(in: watch))
    }

    @Test("a lost child mail and a failed answer are terminals too")
    func lostMailAndFailedAnswerAreTerminals() {
        let lostID = MailID()
        let failedID = MailID()
        let watch = Self.watch(
            observing: [
                Self.output(.runMessage(Self.message), inMail: lostID),
                Self.output(.runSettled(Self.terminal), inMail: failedID),
                SessionOutput(origin: .system, event: .lost(lostID)),
                SessionOutput(
                    origin: .mail([failedID]),
                    event: .answerFailed(AnswerFailure(mailIds: [failedID], reason: .error("watch-failure"))))
            ])

        #expect(Self.isEachChildMailEnded(in: watch))
    }

    @Test("a run event that makes no mail adds no id that waits for a terminal")
    func runEventWithNoMailWaitsForNothing() {
        let watch = Self.watch(observing: [SessionOutput(origin: .system, event: .runSettled(Self.terminal))])

        #expect(Self.isEachChildMailEnded(in: watch))
    }

    @Test("the mail of a call that is not a child does not wait for a terminal of the child rule")
    func mailOfAnotherCallDoesNotCount() {
        let otherID = MailID()
        let watch = Self.watch(observing: [Self.output(.runSettled(Self.otherTerminal), inMail: otherID)])

        #expect(Self.isEachChildMailEnded(in: watch))
        #expect(!watch.hasTerminal(forEachMailOfCalls: [Self.otherToken], and: []))
    }

    @Test("each id that the caller gives must also have a terminal")
    func callerIdsNeedATerminal() {
        let taskID = MailID()
        let messageID = MailID()
        let watch = Self.watch(observing: [Self.answered([taskID])])

        #expect(watch.hasTerminal(forEachMailOfCalls: [Self.token], and: [taskID]))
        #expect(!watch.hasTerminal(forEachMailOfCalls: [Self.token], and: [taskID, messageID]))
    }

    @Test("a tool call is open from its open record to its close record, in each order of the two records")
    func toolCallOpensAndCloses() {
        let open = SessionOutput(origin: .system, event: .toolInvocation(Self.openRecord))
        let close = SessionOutput(origin: .system, event: .toolInvocation(Self.closeRecord))

        #expect(ParentSessionWatch().isEachCallClosed)
        #expect(!Self.watch(observing: [open]).isEachCallClosed)
        #expect(Self.watch(observing: [open, close]).isEachCallClosed)
        #expect(Self.watch(observing: [close, open]).isEachCallClosed)
    }
}
