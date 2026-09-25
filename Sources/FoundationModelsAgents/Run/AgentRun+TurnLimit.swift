import FoundationModels
import FoundationModelsRouter
import Synchronization

/// The one count of the passes of the control loop of one run, and the
/// `maxTurns` limit of its agent (plan.md §5, §9.3).
///
/// In each pass the model generates. Then it calls tools, and the loop goes
/// around again, or it answers, and the loop ends. Each pass records one
/// transcript entry of the kind `.toolCalls` or `.response`, and the Router
/// emits ``SessionEvent/entryRecorded(id:kind:)`` for it. One pass that
/// calls three tools records one entry. The count holds the passes of the
/// task turn and of each delivery turn.
///
/// Two sources feed the count:
///
/// - ``follow(_:onEvent:onLimitHit:)`` reads one session-event subscription
///   for the whole run, and counts each pass entry that it sees.
/// - ``settle(passesIn:partial:)`` counts the pass entries of the transcript
///   after each turn. Thus the count is exact before the run checks the
///   limit, also when the subscription is behind.
///
/// The two sources count the same entries, thus the count is the larger of
/// the two. An event that comes after the settle of its turn does not count
/// a second time.
///
/// A class, because the turn task and the follower task of the run share
/// one count. A `Mutex` guards the count, thus the `Sendable` conformance is
/// compiler-checked.
final class AgentRunTurns: Sendable {
    /// The state that the lock guards.
    private struct Count {
        /// The count of pass events that the follower saw.
        var seen = 0

        /// The count of pass entries in the transcript at the last settle.
        var settled = 0

        /// `true` after the count went above the limit.
        var isLimitHit = false

        /// The count of passes: the larger of the two sources.
        var passes: Int {
            max(seen, settled)
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

    /// The count of the passes so far, over all the turns of the run.
    var count: Int {
        state.withLock { $0.passes }
    }

    /// `true` after the count went above the limit. The run then cancels
    /// its turn, and the cancel ends the run as
    /// ``AgentRunFailure/hitMaxTurns(partial:)``.
    var isLimitHit: Bool {
        state.withLock { $0.isLimitHit }
    }

    /// Adds one pass when `event` records the entry of a pass.
    ///
    /// - Parameter event: An event of the session-event subscription.
    /// - Returns: `true` only for the event that makes the count go above
    ///   the limit the first time.
    func add(_ event: SessionEvent) -> Bool {
        guard Self.isPass(event) else {
            return false
        }
        return state.withLock { count in
            count.seen += 1
            return markLimitHit(in: &count)
        }
    }

    /// Reads the session-event subscription of the run until it finishes,
    /// and counts each pass entry.
    ///
    /// The Router finishes the subscription when the session closes, thus
    /// the read ends with the run.
    ///
    /// - Parameters:
    ///   - events: The session-event subscription of the run.
    ///   - onEvent: Receives each event, for the progress of the run.
    ///   - onLimitHit: Runs one time, when the count goes above the limit.
    ///     The run cancels its turn in it.
    func follow(
        _ events: AsyncStream<SessionEvent>, onEvent: (SessionEvent) -> Void, onLimitHit: () async -> Void
    ) async {
        for await event in events {
            onEvent(event)
            if add(event) {
                await onLimitHit()
            }
        }
    }

    /// Sets the count from the pass entries of `transcript`, and checks the
    /// limit.
    ///
    /// - Parameters:
    ///   - transcript: The transcript of the session after a turn.
    ///   - partial: The text of the last complete turn.
    /// - Throws: ``AgentRunFailure/hitMaxTurns(partial:)`` when the count is
    ///   above the limit.
    func settle(passesIn transcript: Transcript, partial: String) throws(AgentRunFailure) {
        let settled = Self.passCount(in: transcript)
        let isAbove = state.withLock { count in
            count.settled = settled
            _ = markLimitHit(in: &count)
            return count.isLimitHit
        }
        if isAbove {
            throw .hitMaxTurns(partial: partial)
        }
    }

    /// Runs one delivery turn, then sets the count from the transcript and
    /// checks the limit.
    ///
    /// The count comes from the transcript, thus it does not wait for an
    /// event of the turn. A turn that records no `.response` entry, and a
    /// turn that retried and recorded two, each give the correct count.
    ///
    /// - Parameters:
    ///   - lastText: The text of the last complete turn before this turn.
    ///   - dispatch: Runs the turn. It gives the text of the turn, or `nil`
    ///     when it ran no turn.
    ///   - transcript: Gives the transcript of the session after the turn.
    /// - Returns: The text of the turn, or `nil` when the dispatch ran no
    ///   turn.
    /// - Throws: ``AgentRunFailure/hitMaxTurns(partial:)`` when the count is
    ///   above the limit, with the text of the last complete turn. Else the
    ///   error of the turn.
    func deliver(
        lastText: String, dispatch: () async throws -> String?, transcript: () async -> Transcript
    ) async throws -> String? {
        let delivered: String?
        do {
            delivered = try await dispatch()
        } catch {
            throw failure(for: error, partial: lastText)
        }
        try settle(passesIn: await transcript(), partial: delivered ?? lastText)
        return delivered
    }

    /// Gives the error that a turn of the run ends with.
    ///
    /// After the count went above the limit, the run cancelled its turn,
    /// thus the error of that turn is the result of the limit.
    ///
    /// - Parameters:
    ///   - error: The error that the turn threw.
    ///   - partial: The text of the turn so far, or the text of the last
    ///     complete turn.
    /// - Returns: ``AgentRunFailure/hitMaxTurns(partial:)`` after the count
    ///   went above the limit, else `error`.
    func failure(for error: any Error, partial: String) -> any Error {
        isLimitHit ? AgentRunFailure.hitMaxTurns(partial: partial) : error
    }

    /// Sets the limit flag when the count is above the limit.
    ///
    /// - Parameter count: The count that the lock guards.
    /// - Returns: `true` when this call set the flag.
    private func markLimitHit(in count: inout Count) -> Bool {
        guard let limit, count.passes > limit, !count.isLimitHit else {
            return false
        }
        count.isLimitHit = true
        return true
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

    /// Counts the pass entries of `transcript`: each `.toolCalls` and each
    /// `.response` entry.
    ///
    /// - Parameter transcript: A transcript of the session.
    /// - Returns: The count of passes.
    static func passCount(in transcript: Transcript) -> Int {
        transcript.count { entry in
            if case .toolCalls = entry {
                return true
            }
            if case .response = entry {
                return true
            }
            return false
        }
    }
}

extension AgentRun {
    /// Runs one delivery turn with `session.dispatchNextPrompt()`, and sets
    /// the count of ``turns`` from the transcript when the turn returns
    /// (plan.md §5, §8 step 7).
    ///
    /// The follower of the run feeds the progress while the turn runs. When
    /// the turn returns, its text becomes the text tail of the progress.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - lastText: The text of the last complete turn before this turn.
    /// - Returns: The text of the delivery turn, or `nil` when the dispatch
    ///   ran no turn.
    /// - Throws: ``AgentRunFailure/hitMaxTurns(partial:)`` when the count
    ///   goes above the limit, or the error of the delivery turn.
    func dispatchCountingPasses(on session: any RoutedSession, lastText: String) async throws -> String? {
        let delivered = try await turns.deliver(
            lastText: lastText,
            dispatch: { try await session.dispatchNextPrompt() },
            transcript: { await session.transcript })
        if let delivered {
            recordDelivered(delivered)
        }
        return delivered
    }

    /// Counts the passes of each turn of the run from its session-event
    /// subscription, and feeds the progress of the run. When the count goes
    /// above the limit, it cancels the turn in operation.
    ///
    /// - Parameters:
    ///   - events: The session-event subscription of the run, made before
    ///     the task turn. The session closes it when the run ends.
    ///   - session: The session of the run.
    func followPasses(_ events: AsyncStream<SessionEvent>, on session: any RoutedSession) async {
        await turns.follow(events, onEvent: record) {
            await session.cancelCurrentTurn()
        }
    }

    /// Runs the task turn with `prompt`, collects the text of the answer,
    /// and feeds the text tail of the progress. Then sets the count of
    /// ``turns`` from the transcript, and checks the limit.
    ///
    /// The turn stream and the session-event subscription both carry the
    /// tool records of the turn. The follower of the run reads them from the
    /// subscription, thus this read takes only the text events.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - prompt: The prompt of the task turn.
    /// - Returns: The text of the task turn.
    /// - Throws: ``AgentRunFailure/hitMaxTurns(partial:)`` with the text so
    ///   far when the count goes above the limit, else the error of the
    ///   turn.
    func runTaskTurn(on session: any RoutedSession, prompt: String) async throws -> String {
        var text = TurnText()
        do {
            for try await event in await session.streamEvents(to: prompt) where TurnText.isText(event) {
                text.apply(event)
                record(event)
            }
        } catch {
            throw turns.failure(for: error, partial: text.value)
        }
        try turns.settle(passesIn: await session.transcript, partial: text.value)
        return text.value
    }
}

/// The text of the answer of one turn, collected from its events.
///
/// A ``SessionEvent/textReset`` clears the text that came before it.
private struct TurnText {
    /// The text so far.
    private(set) var value = ""

    /// Tells if `event` changes the text of a turn: a text delta or a text
    /// reset.
    ///
    /// - Parameter event: An event of the turn.
    /// - Returns: `true` for a text event.
    static func isText(_ event: SessionEvent) -> Bool {
        if case .textDelta = event {
            return true
        }
        if case .textReset = event {
            return true
        }
        return false
    }

    /// Applies one event of the turn.
    ///
    /// - Parameter event: The event.
    mutating func apply(_ event: SessionEvent) {
        if case .textDelta(let fragment) = event {
            value += fragment
        }
        if case .textReset = event {
            value = ""
        }
    }
}
