import FoundationModelsRouter
import Synchronization

/// The part of the life of a run after its setup (plan.md §8 steps 6 to 8).
///
/// The phase tells the runner if the run holds a place in the run limit, and
/// tells `check agent` if the run waits for the runs that it started.
enum AgentRunPhase: Sendable, Equatable {
    /// The run is in its task turn: the turn of its prompt.
    case taskTurn

    /// The task turn ended, and the run waits for a run that it started to
    /// end. A run in this phase holds no place in the run limit
    /// (plan.md §9.3).
    case waitingForChildren

    /// The task turn ended, and the run is in a child-delivery turn or in a
    /// final-answer turn, or looks for a staged post to deliver.
    case delivery
}

/// The run that calls the `agents` tool, as the tool sees it
/// (plan.md §9.3, children and depth).
///
/// `start agent` uses it to give a child its depth and its inherited slot,
/// and the child adds itself to ``children``. A root session that is not a
/// run has no such value.
struct ParentRun: Sendable {
    /// The depth of the calling run. A host-started run has depth one.
    let depth: Int

    /// The slot of the session of the calling run.
    let slot: ModelSlot

    /// The runs that the calling run started.
    let children: AgentRunChildren
}

/// The runs that one run started, and a signal each time one of them ends
/// (plan.md §9.3, children).
///
/// A child adds itself before its turn starts, and signals after it posts
/// its final message and records its final state. Thus the post of an ended
/// child is staged in the session of the parent when the parent gets the
/// signal.
///
/// A class, because the run, its `agents` tool, and each child share one
/// list. A `Mutex` guards the list, thus the `Sendable` conformance is
/// compiler-checked.
final class AgentRunChildren: Sendable {
    /// The state that the lock guards.
    private struct Storage {
        /// The runs that the parent started, in start order.
        var runs: [AgentRun] = []

        /// `true` after the parent cancelled its open children. A child that
        /// comes later is cancelled at once.
        var isClosed = false
    }

    /// One element for each child that ended. The stream keeps each element
    /// until the parent reads it.
    let endings: AsyncStream<Void>

    /// The continuation of ``endings``.
    private let endingsContinuation: AsyncStream<Void>.Continuation

    /// The list and its closed flag.
    private let storage = Mutex(Storage())

    /// Makes an empty list.
    init() {
        (endings, endingsContinuation) = AsyncStream<Void>.makeStream()
    }

    /// The count of children whose turn has not ended.
    var openCount: Int {
        storage.withLock { storage in storage.runs.count(where: { $0.state == .running }) }
    }

    /// Adds a child that is about to start its turn.
    ///
    /// - Parameter child: The new run.
    /// - Returns: `false` when the parent already cancelled its children.
    ///   The caller then cancels `child`.
    func add(_ child: AgentRun) -> Bool {
        storage.withLock { storage in
            guard !storage.isClosed else {
                return false
            }
            storage.runs.append(child)
            return true
        }
    }

    /// Tells the parent that one child ended. The child calls it after it
    /// recorded its final state.
    func childDidEnd() {
        endingsContinuation.yield()
    }

    /// Cancels each open child, and waits for each to end. A child that
    /// comes later is cancelled at once.
    func cancelOpenRuns() async {
        let open = storage.withLock { storage in
            storage.isClosed = true
            return storage.runs.filter { $0.state == .running }
        }
        for child in open {
            child.cancel()
        }
        for child in open {
            _ = await child.finalState()
        }
    }
}

extension AgentRun {
    /// The prompt of a final-answer turn (plan.md §8 step 8). The run sends
    /// it when no child is open and no post is unread, after a delivery turn.
    static let finalAnswerPrompt = "All agents that you started have finished. Give your full final answer."

    /// The sentence that `check agent` adds after the task turn while
    /// children are open: "It waits for `N` agents that it started."
    /// `nil` in the task turn, or when no child is open.
    var waitingSentence: String? {
        let open = children.openCount
        guard phase != .taskTurn, open > 0 else {
            return nil
        }
        return "It waits for \(open) agents that it started."
    }

    /// Delivers the final messages of the children, and gives the result
    /// of the run (plan.md §8 steps 7 and 8).
    ///
    /// While a child is open, the run waits for a child to end. It then
    /// calls `session.dispatchNextPrompt()` through
    /// ``dispatchCountingPasses(on:lastText:)``: the Router runs one turn
    /// with the staged posts, and the model can start more children.
    ///
    /// The loop is quiet when no child was open before a dispatch and the
    /// dispatch ran no turn. Thus no post stays unread. When a delivery turn
    /// ran since the last final-answer turn, the run then runs a
    /// final-answer turn (``dispatchFinalAnswer(on:lastText:)``). That turn
    /// can start more children, and the loop goes on. When the loop is quiet
    /// and no delivery turn ran since the last final-answer turn, the loop
    /// ends. Thus a run that started no child runs no final-answer turn, and
    /// its result is the text of its task turn.
    ///
    /// The passes of each delivery turn and of each final-answer turn add to
    /// the `maxTurns` count of the run. These turns do not check the run
    /// limit. The run holds no place in the limit while it waits.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - taskTurnText: The text of the task turn.
    /// - Returns: The text of the last turn: the last final-answer turn, or
    ///   the task turn of a run that started no child.
    /// - Throws: `CancellationError` when the run is cancelled while it
    ///   waits, ``AgentRunFailure/hitMaxTurns(partial:)`` when the count
    ///   goes above the `maxTurns` limit, or the error of a turn.
    func finishAfterChildren(on session: any RoutedSession, taskTurnText: String) async throws -> String {
        var endings = children.endings.makeAsyncIterator()
        var text = taskTurnText
        var isFinalAnswerDue = false
        while true {
            let hadOpenChildren = children.openCount > 0
            if hadOpenChildren {
                enter(.waitingForChildren)
                guard await endings.next() != nil else {
                    throw CancellationError()
                }
            }
            enter(.delivery)
            try Task.checkCancellation()
            if let delivered = try await dispatchCountingPasses(on: session, lastText: text) {
                text = delivered
                isFinalAnswerDue = true
                continue
            }
            guard !hadOpenChildren else {
                continue
            }
            guard isFinalAnswerDue else {
                return text
            }
            text = try await dispatchFinalAnswer(on: session, lastText: text)
            isFinalAnswerDue = false
        }
    }

    /// Runs one final-answer turn: it queues ``finalAnswerPrompt`` in the
    /// session, and dispatches it through
    /// ``dispatchCountingPasses(on:lastText:)`` (plan.md §8 step 8).
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - lastText: The text of the last complete turn before this turn.
    /// - Returns: The text of the final-answer turn, or `lastText` when the
    ///   dispatch ran no turn.
    /// - Throws: ``AgentRunFailure/hitMaxTurns(partial:)`` when the count
    ///   goes above the `maxTurns` limit, or the error of the turn.
    private func dispatchFinalAnswer(on session: any RoutedSession, lastText: String) async throws -> String {
        await session.enqueue(prompt: Self.finalAnswerPrompt)
        return try await dispatchCountingPasses(on: session, lastText: lastText) ?? lastText
    }
}
