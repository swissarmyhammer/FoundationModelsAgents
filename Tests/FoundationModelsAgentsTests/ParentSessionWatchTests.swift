@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins the message rule of the watch of a parent session: each message that
/// a child sent is delivered only when the prompts of the answered answers
/// hold its mail line one time for each message.
///
/// One child can send the same text two times with one completion token.
/// Thus the rule counts the mail lines, and a prompt that holds one line
/// delivers one message only.
@Suite("Parent session watch")
struct ParentSessionWatchTests {
    /// The completion token of the `start agent` call of the child.
    private static let token = "watch-child-token"

    /// The text of each message of the child.
    private static let messageText = "watch-message: half of the files are done"

    /// The text of a prompt that holds no mail.
    private static let taskPrompt = "watch-task: divide the task"

    /// A message of the child, as the Router sends it in a `runMessage`
    /// event.
    private static let message = OperationEvent(
        tool: ToolVocabulary.agentsToolName, op: StartAgent.opString, correlationID: token, kind: .message,
        detail: messageText)

    /// Gives a watch that observed one `runMessage` event for each entry of
    /// `messages`.
    ///
    /// - Parameter messages: The messages, in event order.
    /// - Returns: The watch.
    private static func watch(observing messages: [OperationEvent]) -> ParentSessionWatch {
        let watch = ParentSessionWatch()
        for message in messages {
            watch.observe(.runMessage(message))
        }
        return watch
    }

    @Test("a message is delivered when an answered prompt holds its mail line")
    func messageInAnsweredPromptIsDelivered() {
        let watch = Self.watch(observing: [Self.message])

        #expect(watch.isEachMessageDelivered(inAnsweredPrompts: [ParentSessionWatch.mailLine(of: Self.message)]))
    }

    @Test("a message is not delivered when the answered prompts hold its text but not its mail line")
    func messageWithoutMailLineIsNotDelivered() {
        let watch = Self.watch(observing: [Self.message])

        #expect(!watch.isEachMessageDelivered(inAnsweredPrompts: [Self.taskPrompt, Self.messageText]))
    }

    @Test("two messages with one text need two mail lines in the answered prompts")
    func twoEqualMessagesNeedTwoMailLines() {
        let watch = Self.watch(observing: [Self.message, Self.message])
        let line = ParentSessionWatch.mailLine(of: Self.message)

        #expect(!watch.isEachMessageDelivered(inAnsweredPrompts: [Self.taskPrompt, line]))
        #expect(watch.isEachMessageDelivered(inAnsweredPrompts: [Self.taskPrompt, "\(line)\n\(line)"]))
    }

    @Test("a watch that observed no message has each message delivered")
    func noMessageIsDelivered() {
        #expect(ParentSessionWatch().isEachMessageDelivered(inAnsweredPrompts: []))
    }
}
