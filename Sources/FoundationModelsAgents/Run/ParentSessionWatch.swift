import Foundation
import FoundationModelsExtras
import FoundationModelsRouter
import Synchronization

/// The mail and the tool calls of the session of a run, by id, as the
/// session-event subscription of the run tells them.
///
/// The run gives each output of its session-event subscription to
/// ``observe(_:)``. The watch keeps three records:
///
/// - The id of each mail of a run event, by the completion token of its
///   call: the origin `.mail([id])` of each ``SessionEvent/runMessage(_:)``
///   and ``SessionEvent/runSettled(_:)`` output. The idle rule reads only
///   the ids of the calls that started the children of the run. A run that
///   ends in its call, for example the run of a synchronous tool that posted
///   progress, also makes mail for its terminal event. That mail starts no
///   submission: it goes with the next submission, thus no terminal event
///   comes for it when no other mail comes. An event that makes no mail has
///   the origin of the work that sent it. That origin holds no id, or the
///   ids of an answer, and an answer always gets a terminal event. Thus each
///   id of such an origin also goes in this set, with no harm.
/// - The id of each mail that has a terminal event: the `mailIds` of
///   ``SessionEvent/answered(_:)`` and of ``SessionEvent/answerFailed(_:)``,
///   ``SessionEvent/cancelled(_:)``, and ``SessionEvent/lost(_:)``.
/// - The completion token of each tool call whose open and close
///   ``SessionEvent/toolInvocation(_:toolCallID:)`` records came.
///
/// The idle rule reads the sets (``isEachCallClosed`` and
/// ``hasTerminal(forEachMailOfCalls:and:)``). The rule uses sets, not the order
/// of the events: the Router can send ``SessionEvent/mailDelivered(_:)`` and
/// the terminal event of a mail before or after the output of the run event
/// that the mail holds.
///
/// A tool call posts its open record before its body starts, thus before
/// the call gives the model its output or the pending envelope of a
/// background run. The body of a run that makes mail posts its terminal
/// event and waits until the journal recorded it. The journal sends the
/// output of that event at that time. Then the call posts its close record.
/// A message of a child goes the same way: the post waits until the journal
/// recorded it. Thus the output of each run event of a call comes before the
/// close record of that call.
///
/// Before the run closes its session, it waits until the run plane settled
/// the call of each run that it started (``waitForSettlement(ofCalls:)``).
/// That wait goes by token through the run plane, not through the live
/// ``SessionEvent/runSettled(_:)``. A cancel (`cancelAll()`) can drop the
/// live events of the answer that it stopped, also the `runSettled` of a
/// call that the answer started. Thus a wait for the live event can wait
/// for ever.
///
/// A class, because the follower of the run and the close of the run share
/// one watch. A `Mutex` guards the state, thus the `Sendable` conformance is
/// compiler-checked.
final class ParentSessionWatch: Sendable {
    /// The state that the lock guards.
    private struct State {
        /// The id of each mail of a run event, by the completion token of
        /// its call.
        var runMail: [String: Set<MailID>] = [:]

        /// The id of each mail that has a terminal event.
        var endedMail: Set<MailID> = []

        /// The completion token of each tool call whose open record came.
        var openedCalls: Set<String> = []

        /// The completion token of each tool call whose close record came.
        var closedCalls: Set<String> = []
    }

    /// The state of the watch.
    private let state = Mutex(State())

    /// Makes an empty watch.
    init() {}

    /// Applies one output of the session-event subscription of the run.
    ///
    /// - Parameter output: The output.
    func observe(_ output: SessionOutput) {
        state.withLock { state in
            switch output.event {
            case .runMessage(let event), .runSettled(let event):
                if case .mail(let ids) = output.origin {
                    state.runMail[event.correlationID, default: []].formUnion(ids)
                }
            case .answered(let answer):
                state.endedMail.formUnion(answer.mailIds)
            case .answerFailed(let failure):
                state.endedMail.formUnion(failure.mailIds)
            case .cancelled(let id), .lost(let id):
                state.endedMail.insert(id)
            case .toolInvocation(let record, _):
                if record.closedAt == nil {
                    state.openedCalls.insert(record.correlationID)
                } else {
                    state.closedCalls.insert(record.correlationID)
                }
            default:
                break
            }
        }
    }

    /// `true` when the close record of each tool call whose open record came
    /// also came. A call that runs, also a background run of a call, keeps
    /// this value `false`.
    var isEachCallClosed: Bool {
        state.withLock { $0.openedCalls.isSubset(of: $0.closedCalls) }
    }

    /// Tells if each mail of the run events of the calls `tokens`, and each
    /// mail of `ids`, has a terminal event.
    ///
    /// - Parameters:
    ///   - tokens: The completion token of each call whose mail needs a
    ///     terminal event, for example the call of each child.
    ///   - ids: More ids that need a terminal event, for example the
    ///     user-type mail of the run.
    /// - Returns: `true` when each of these ids has a terminal event.
    func hasTerminal(forEachMailOfCalls tokens: some Sequence<String>, and ids: some Sequence<MailID>) -> Bool {
        state.withLock { state in
            tokens.allSatisfy { state.runMail[$0, default: []].isSubset(of: state.endedMail) }
                && ids.allSatisfy(state.endedMail.contains)
        }
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
