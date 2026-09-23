import FoundationModelsRouter
import Synchronization

/// The count of the passes of the control loop of one run, and the
/// `maxTurns` limit of its agent (plan.md §5, §9.3).
///
/// In each pass the model generates. Then it calls tools, and the loop goes
/// around again, or it answers, and the loop ends. Each pass records one
/// transcript entry, and the Router emits
/// ``SessionEvent/entryRecorded(id:kind:)`` with the kind `.toolCalls` or
/// `.response` for it. One pass that calls three tools records one entry.
/// The count holds the passes of the task turn and of each delivery turn.
///
/// A class, because the turn task of the run adds to the count and the
/// run reads it. A `Mutex` guards the count, thus the `Sendable`
/// conformance is compiler-checked.
final class AgentRunTurns: Sendable {
    /// The `maxTurns` limit of the agent, or `nil` for no limit.
    let limit: Int?

    /// The count of the passes so far.
    private let passes = Mutex(0)

    /// Makes a count of zero.
    ///
    /// - Parameter limit: The `maxTurns` limit of the agent, or `nil` for
    ///   no limit.
    init(limit: Int?) {
        self.limit = limit
    }

    /// The count of the passes so far, over all the turns of the run.
    var count: Int {
        passes.withLock { $0 }
    }

    /// Adds one pass when `event` records the entry of a pass.
    ///
    /// - Parameters:
    ///   - event: An event of a turn of the run.
    ///   - partial: The text of the turn so far.
    /// - Throws: ``AgentRunFailure/hitMaxTurns(partial:)`` when the count
    ///   goes above ``limit``.
    func add(_ event: SessionEvent, partial: String) throws(AgentRunFailure) {
        guard Self.isPass(event) else {
            return
        }
        let count = passes.withLock { passes in
            passes += 1
            return passes
        }
        if let limit, count > limit {
            throw .hitMaxTurns(partial: partial)
        }
    }

    /// Tells if `event` records the entry of one pass: a `.toolCalls` or a
    /// `.response` entry.
    ///
    /// - Parameter event: An event of a turn.
    /// - Returns: `true` for the entry of a pass.
    static func isPass(_ event: SessionEvent) -> Bool {
        guard case .entryRecorded(_, let kind) = event else {
            return false
        }
        switch kind {
        case .toolCalls, .response:
            return true
        case .reasoning:
            return false
        }
    }

    /// Tells if `event` records the entry of the answer: the last pass of a
    /// turn.
    ///
    /// - Parameter event: An event of a turn.
    /// - Returns: `true` for a `.response` entry.
    static func isAnswer(_ event: SessionEvent) -> Bool {
        guard case .entryRecorded(_, .response) = event else {
            return false
        }
        return true
    }
}

extension AgentRun {
    /// Runs one delivery turn with `session.dispatchNextPrompt()`, and adds
    /// the passes of that turn to ``turns`` (plan.md §5, §8 step 7).
    ///
    /// `dispatchNextPrompt()` gives only text. The Router also sends each
    /// event of the turn to each `streamSessionEvents()` subscription, thus
    /// the run subscribes before the dispatch. When the dispatch gives
    /// text, the subscription holds each event of the turn. The run reads
    /// them up to the entry of the answer, which is the last pass.
    ///
    /// - Parameter session: The session of the run.
    /// - Returns: The text of the delivery turn, or `nil` when the dispatch
    ///   ran no turn.
    /// - Throws: ``AgentRunFailure/hitMaxTurns(partial:)`` when the count
    ///   goes above the limit, `CancellationError` when the run is cancelled
    ///   while it reads, or the error of the delivery turn.
    func dispatchCountingPasses(on session: any RoutedSession) async throws -> String? {
        let events = await session.streamSessionEvents()
        guard let delivered = try await session.dispatchNextPrompt() else {
            return nil
        }
        for await event in events {
            try turns.add(event, partial: delivered)
            if AgentRunTurns.isAnswer(event) {
                return delivered
            }
        }
        throw CancellationError()
    }
}
