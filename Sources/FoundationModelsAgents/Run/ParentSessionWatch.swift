import Foundation
import FoundationModelsRouter
import Synchronization

/// The background runs that settled in the session of a run (plan.md §9.2).
///
/// The run gives each event of its session-event subscription to
/// ``observe(_:)``. The watch keeps the detail of each terminal that the
/// Router recorded. Two parts of the run read it:
///
/// - The idle rule reads the detail of each background call of the session
///   (``detail(ofSettledCall:)``): the session is idle only when a prompt
///   holds that detail.
/// - Before the run closes its session, it waits until the Router recorded
///   the final message of each run that it started
///   (``waitForSettlement(ofCalls:)``). Thus the recording of the session
///   holds each final message.
///
/// The key is the completion token of the call. The Router sends
/// ``SessionEvent/runSettled(_:)`` with that token as the `correlationID` of
/// the terminal.
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

        /// The waits for the settlement of a call, by token.
        var settlementWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

        /// `true` after the session-event subscription finished. Each wait
        /// then returns at once.
        var isFinished = false
    }

    /// The state of the watch.
    private let state = Mutex(State())

    /// Makes an empty watch.
    init() {}

    /// Applies one event of the session-event subscription of the run, and
    /// resumes each wait that the event completes.
    ///
    /// - Parameter event: The event.
    func observe(_ event: SessionEvent) {
        if case .runSettled(let terminal) = event {
            resume(takingSettlementWaiters(of: terminal))
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

    /// Ends the watch when the session-event subscription finished. Each
    /// wait returns, now and later.
    func finish() {
        let waiters = state.withLock { state in
            state.isFinished = true
            let waiters = Array(state.settlementWaiters.values.joined())
            state.settlementWaiters = [:]
            return waiters
        }
        resume(waiters)
    }

    /// Waits until the Router recorded the terminal of each call of `tokens`.
    ///
    /// - Parameter tokens: The completion tokens of the calls.
    func waitForSettlement(ofCalls tokens: [String]) async {
        for token in tokens {
            await waitForSettlement(ofCall: token)
        }
    }

    /// Waits until the Router recorded the terminal of the call `token`.
    ///
    /// - Parameter token: The completion token of the call.
    private func waitForSettlement(ofCall token: String) async {
        await withCheckedContinuation { continuation in
            let isDone = state.withLock { state in
                guard !state.isFinished, state.settledDetails[token] == nil else {
                    return true
                }
                state.settlementWaiters[token, default: []].append(continuation)
                return false
            }
            if isDone {
                continuation.resume()
            }
        }
    }

    /// Records `terminal`, and takes the waits of its call.
    ///
    /// - Parameter terminal: The terminal that the Router recorded.
    /// - Returns: The waits to resume.
    private func takingSettlementWaiters(of terminal: OperationEvent) -> [CheckedContinuation<Void, Never>] {
        state.withLock { state in
            state.settledDetails[terminal.correlationID] = terminal.detail
            return state.settlementWaiters.removeValue(forKey: terminal.correlationID) ?? []
        }
    }

    /// Resumes each wait of `waiters`.
    ///
    /// - Parameter waiters: The waits.
    private func resume(_ waiters: [CheckedContinuation<Void, Never>]) {
        for waiter in waiters {
            waiter.resume()
        }
    }
}
