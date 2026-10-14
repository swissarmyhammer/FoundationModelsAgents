import Foundation
import FoundationModelsExtras
import FoundationModelsRouter
import Synchronization

/// The background runs that settled in the session of a run.
///
/// The run gives each event of its session-event subscription to
/// ``observe(_:)``. The watch keeps the detail of each terminal that the
/// Router sent live (``SessionEvent/runSettled(_:)``). The idle rule reads
/// the detail of each background call of the session
/// (``detail(ofSettledCall:)``): the session is idle only when a prompt
/// holds that detail. The key is the completion token of the call. The
/// Router sends ``SessionEvent/runSettled(_:)`` with that token as the
/// `correlationID` of the terminal.
///
/// Before the run closes its session, it waits until the run plane settled
/// the call of each run that it started (``waitForSettlement(ofCalls:)``).
/// That wait goes by token through the run plane, not through the live
/// ``SessionEvent/runSettled(_:)``. A cancel (`cancelAll()`) can drop the
/// live events of the answer that it stopped, also the `runSettled` of a
/// call that the answer started. Thus a wait for the live event can wait
/// for ever.
///
/// The watch also keeps each message that a running child sent
/// (``SessionEvent/runMessage(_:)``), in order, for each token. One child can
/// send many messages with one token, thus the watch keeps a list for each
/// token and not one message. The idle rule reads them
/// (``isEachMessageDelivered(inAnsweredPrompts:)``): the session is idle only
/// when the answered prompts hold the mail line of each message.
///
/// A class, because the follower of the run and the close of the run share
/// one watch. A `Mutex` guards the state, thus the `Sendable` conformance is
/// compiler-checked.
final class ParentSessionWatch: Sendable {
    /// The words of the Router for the state of a message in its mail line
    /// (`OperationEventSegment.renderedLine(for:)` of the Router).
    static let messageState = "message, still running"

    /// The state that the lock guards.
    private struct State {
        /// The detail of each terminal that the Router recorded, by the
        /// token of its call.
        var settledDetails: [String: String] = [:]

        /// The messages that each running child sent, in event order, by
        /// the token of its call.
        var messages: [String: [OperationEvent]] = [:]
    }

    /// The state of the watch.
    private let state = Mutex(State())

    /// Makes an empty watch.
    init() {}

    /// Applies one event of the session-event subscription of the run.
    ///
    /// - Parameter event: The event.
    func observe(_ event: SessionEvent) {
        if case .runSettled(let terminal) = event {
            state.withLock { $0.settledDetails[terminal.correlationID] = terminal.detail }
        }
        if case .runMessage(let message) = event {
            state.withLock { $0.messages[message.correlationID, default: []].append(message) }
        }
    }

    /// Gives the line that the Router puts in a prompt for the mail of
    /// `message`: "[tool] op (token) message, still running: text".
    ///
    /// - Parameter message: A message of a running child.
    /// - Returns: The mail line.
    static func mailLine(of message: OperationEvent) -> String {
        "[\(message.tool)] \(message.op) (\(message.correlationID)) \(messageState): \(message.detail)"
    }

    /// Tells if the session delivered each message that a child sent.
    ///
    /// A message is delivered when an answered prompt holds its mail line
    /// (``mailLine(of:)``). Two messages with the same mail line need two
    /// such lines, thus the rule counts the lines and does not only look for
    /// one.
    ///
    /// - Parameter prompts: The text of each prompt that an answer that the
    ///   run processed answered
    ///   (``AgentRunAnswers/answeredPromptTexts(in:)``).
    /// - Returns: `true` when the prompts hold the mail line of each message
    ///   one time for each message.
    func isEachMessageDelivered(inAnsweredPrompts prompts: [String]) -> Bool {
        let messages = state.withLock { Array($0.messages.values.joined()) }
        let needed = Dictionary(messages.map { (Self.mailLine(of: $0), 1) }, uniquingKeysWith: +)
        return needed.allSatisfy { line, count in
            prompts.reduce(0) { total, prompt in total + Self.count(of: line, in: prompt) } >= count
        }
    }

    /// Gives the count of the places where `line` stands in `text`, with no
    /// overlap.
    ///
    /// - Parameters:
    ///   - line: The text to find.
    ///   - text: The text to look in.
    /// - Returns: The count.
    private static func count(of line: String, in text: String) -> Int {
        text.components(separatedBy: line).count - 1
    }

    /// Gives the detail of the terminal of the call `token`.
    ///
    /// - Parameter token: The completion token of the call.
    /// - Returns: The detail, or `nil` when the Router recorded no terminal
    ///   for the call yet.
    func detail(ofSettledCall token: String) -> String? {
        state.withLock { $0.settledDetails[token] }
    }

    /// Waits until the run plane settled each call of `calls`.
    ///
    /// For each call, the wait goes by its completion token through the run
    /// plane (`ToolContext.wait(completionToken:seconds:)`). The run plane
    /// settles the call when the body of the call posts its terminal, also
    /// when a cancel dropped the live ``SessionEvent/runSettled(_:)`` of that
    /// terminal. Thus the wait does not use the live event. A call that is
    /// settled already, or a token that the run plane does not know, returns
    /// at once.
    ///
    /// - Parameter calls: The context of each `start agent` call, in order.
    func waitForSettlement(ofCalls calls: [ToolContext]) async {
        for call in calls {
            _ = await call.wait(completionToken: call.completionToken, seconds: nil)
        }
    }
}
