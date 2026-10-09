import FoundationModelsRouter
import Synchronization

/// The one count of the passes of the control loop of one run, and the
/// `maxTurns` limit of its agent.
///
/// In each pass the model generates. Then it calls tools, and the loop goes
/// around again, or it answers, and the loop ends. The count holds the passes
/// of each submission of the session of the run: the answer of the task
/// prompt, and each answer to the final message of a run that it started.
///
/// The run reads its one session-event subscription, and gives each event to
/// ``apply(_:)``. Two kinds of events feed the count:
///
/// - The live events count the passes of the submission in operation. Each
///   ``SessionEvent/generationCall(_:)`` is one pass. An open
///   ``SessionEvent/toolInvocation(_:)`` record shows that at least one pass
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
    /// session, and ends as ``AgentRunFailure/hitMaxTurns(partial:)``.
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
        if case .toolInvocation(let record) = event, record.closedAt == nil {
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
