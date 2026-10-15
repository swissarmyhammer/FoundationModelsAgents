import FoundationModelsRouter
import Synchronization

/// The one count of the passes of the control loop of one run, and the
/// `maxTurns` limit of its agent.
///
/// In each pass the model generates. Then it calls tools, and the loop goes
/// around again, or it answers, and the loop ends. The count holds the passes
/// of each submission of the session of the run: the answer of the task
/// prompt, each answer to a message from the caller, and each answer to run
/// mail (a message or the final message of a run that it started). The pump
/// can put more than one mail in one answer, and that answer counts one time.
/// A summarizer call of a compaction opens no submission and sends no
/// ``SessionEvent/generationCall(_:)``, thus it does not count.
///
/// When the count goes above the limit, the follower of the run stops its
/// session with `cancelAll()`, and the run ends as
/// ``AgentRunFailure/hitMaxTurns(partial:)``. When a generation call that
/// ended with response text makes the count go above the limit, the stop
/// comes at the end of that answer: no more pass can start in it, and the
/// partial text is its reply. Each other event that makes the count go above
/// the limit stops the session at once. The open answer then ends with
/// ``SessionEvent/answerFailed(_:)``. The session sends no more events of
/// the stopped answer, also not its ``SessionEvent/submissionEnded(_:)``.
/// Thus the count of that submission stays its live count. The run ends at
/// that time, thus this does not change the result.
///
/// The run reads its one session-event subscription, and gives each event to
/// ``apply(_:)``. Two kinds of events feed the count:
///
/// - The live events count the passes of the submission in operation. Each
///   ``SessionEvent/generationCall(_:)`` is one pass. An open
///   ``SessionEvent/toolInvocation(_:toolCallID:)`` record shows that at least one pass
///   ran: the tools of a pass can open before the generation call of that
///   pass comes, and a backend that reports no usage gives no generation
///   call at all. Thus the live count of a submission is its count of
///   generation calls, and at least one after a tool open.
/// - The recorded entries correct the count. The Router records the entries
///   of a submission at its end: one ``SessionEvent/entryRecorded(id:kind:)``
///   for each `.toolCalls` or `.response` entry, one for each pass. At
///   ``SessionEvent/submissionEnded(_:)``, the count of these entries replaces
///   the live count of that submission.
///
/// A class, because the follower of the run and the readers of its progress
/// share one count. A `Mutex` guards the count, thus the `Sendable`
/// conformance is compiler-checked.
final class AgentRunTurns: Sendable {
    /// The state that the lock guards.
    private struct Count {
        /// The passes of the submissions that ended, from their recorded
        /// entries.
        var settled = 0

        /// The generation calls of the submission in operation.
        var generationCalls = 0

        /// `true` after a tool of the submission in operation opened.
        var hasToolOpen = false

        /// The pass entries that the submission in operation recorded.
        var recorded = 0

        /// `true` after the count went above the limit.
        var isLimitHit = false

        /// The live count of the submission in operation.
        var live: Int {
            max(generationCalls, hasToolOpen ? 1 : 0)
        }

        /// The count of passes.
        var passes: Int {
            settled + max(live, recorded)
        }
    }

    /// The `maxTurns` limit of the agent, or `nil` for no limit.
    let limit: Int?

    /// The count and the limit flag.
    private let state = Mutex(Count())

    /// Makes a count of zero.
    ///
    /// - Parameter limit: The `maxTurns` limit of the agent, or `nil` for
    ///   no limit.
    init(limit: Int?) {
        self.limit = limit
    }

    /// The count of the passes so far, over all the submissions of the run.
    var count: Int {
        state.withLock { $0.passes }
    }

    /// `true` after the count went above the limit. The run then stops its
    /// session with `cancelAll()`, and ends as
    /// ``AgentRunFailure/hitMaxTurns(partial:)``.
    var isLimitHit: Bool {
        state.withLock { $0.isLimitHit }
    }

    /// Applies one event of the session-event subscription of the run.
    ///
    /// - Parameter event: The event.
    /// - Returns: `true` only for the event that makes the count go above
    ///   the limit the first time.
    func apply(_ event: SessionEvent) -> Bool {
        if case .submissionStarted = event {
            startSubmission()
            return false
        }
        if case .submissionEnded = event {
            return endSubmission()
        }
        if case .generationCall = event {
            return update { $0.generationCalls += 1 }
        }
        if case .toolInvocation(let record, _) = event, record.closedAt == nil {
            return update { $0.hasToolOpen = true }
        }
        if case .entryRecorded(_, let kind) = event, Self.isPass(kind) {
            return update { $0.recorded += 1 }
        }
        return false
    }

    /// Starts the live count of a new submission.
    func startSubmission() {
        state.withLock { count in
            count.generationCalls = 0
            count.hasToolOpen = false
            count.recorded = 0
        }
    }

    /// Ends the submission in operation: its recorded pass entries replace
    /// its live count.
    ///
    /// - Returns: `true` when this makes the count go above the limit the
    ///   first time.
    func endSubmission() -> Bool {
        update { count in
            count.settled += count.recorded
            count.generationCalls = 0
            count.hasToolOpen = false
            count.recorded = 0
        }
    }

    /// Changes the count, then sets the limit flag when the count is above
    /// the limit.
    ///
    /// - Parameter change: The change of the count.
    /// - Returns: `true` when this call set the flag.
    private func update(_ change: (inout Count) -> Void) -> Bool {
        state.withLock { count in
            change(&count)
            guard let limit, count.passes > limit, !count.isLimitHit else {
                return false
            }
            count.isLimitHit = true
            return true
        }
    }

    /// Tells if a recorded entry of `kind` is the entry of one pass: a
    /// `.toolCalls` or a `.response` entry.
    ///
    /// - Parameter kind: The kind of a recorded entry.
    /// - Returns: `true` for the entry of a pass.
    static func isPass(_ kind: RecordedEntryKind) -> Bool {
        switch kind {
        case .toolCalls, .response:
            true
        case .reasoning:
            false
        }
    }
}

/// The rule that decides when a run stops its session with `cancelAll()`
/// after the count of passes went above the `maxTurns` limit.
///
/// The follower of the run gives the rule each event, and each signal of an
/// event. The rule has no other part beside it.
///
/// - A generation call that ended with response text ended its attempt, thus
///   no more pass can start in that answer. When that call makes the count go
///   above the limit, the stop comes with the
///   ``AgentRunSignal/limitHit(partial:)`` signal at the end of that answer.
///   The partial text is then the reply of that answer. The Router sends the
///   generation call before `answered`, thus a stop at the generation call can
///   drop the reply, and the partial text is then the reply of an earlier
///   answer.
/// - Each other event that makes the count go above the limit stops the
///   session at once, for example a generation call that ended with a tool
///   call: the tool and the next pass must not run.
struct AgentRunLimitStop: Sendable {
    /// What the follower does after one step of the rule.
    enum Action: Sendable, Equatable {
        /// The follower does not stop the session.
        case none

        /// The follower stops the session with `cancelAll()`.
        case stop
    }

    /// `true` after a generation call that ended with response text made the
    /// count go above the limit, until the end of its answer.
    private var isStopAtAnswerEnd = false

    /// Gives the action after the count of passes applied one event.
    ///
    /// - Parameters:
    ///   - event: The event.
    ///   - wentAboveLimit: `true` when this event made the count go above the
    ///     limit the first time (``AgentRunTurns/apply(_:)``).
    /// - Returns: ``Action/stop`` for an event above the limit that is not a
    ///   generation call with response text, else ``Action/none``.
    mutating func action(after event: SessionEvent, wentAboveLimit: Bool) -> Action {
        guard wentAboveLimit else {
            return .none
        }
        if Self.endsAttemptWithText(event) {
            isStopAtAnswerEnd = true
            return .none
        }
        return .stop
    }

    /// Gives the action at one signal of the run.
    ///
    /// - Parameter signal: The signal of an event.
    /// - Returns: ``Action/stop`` for the ``AgentRunSignal/limitHit(partial:)``
    ///   signal after a generation call with response text went above the
    ///   limit, else ``Action/none``.
    mutating func action(at signal: AgentRunSignal) -> Action {
        guard case .limitHit = signal, isStopAtAnswerEnd else {
            return .none
        }
        isStopAtAnswerEnd = false
        return .stop
    }

    /// Tells if `event` is a generation call that ended with response text.
    ///
    /// - Parameter event: A session event.
    /// - Returns: `true` for a ``SessionEvent/generationCall(_:)`` whose entry
    ///   kind is `.text`.
    static func endsAttemptWithText(_ event: SessionEvent) -> Bool {
        if case .generationCall(let usage) = event {
            return usage.entryKind == .text
        }
        return false
    }
}
