import FoundationModelsRouter
import Synchronization

/// The part of the life of a run after its setup (plan.md §8 steps 6 to 8).
///
/// The phase tells the runner if the run holds a place in the run limit, and
/// tells `check agent` if the run waits for the runs that it started.
enum AgentRunPhase: Sendable, Equatable {
    /// The run is in the answer of its task prompt.
    case taskTurn

    /// No answer of the run is open after its first answer: the run waits
    /// for the final messages of the runs that it started. A run in this
    /// phase holds no place in the run limit (plan.md §9.3).
    ///
    /// The phase does not count the children. The body of a `start agent`
    /// call adds its run after the answer that made the call can end, and a
    /// run that is not idle after an answer waits for mail in each case.
    case waitingForChildren

    /// The run is in an answer to the final message of a run that it
    /// started.
    case delivery

    /// Gives the phase of a run after one session event.
    ///
    /// - Parameters:
    ///   - answers: The answers of the session after the event.
    ///   - current: The phase before the event.
    init(after answers: AgentRunAnswers, current: AgentRunPhase) {
        if answers.isAnswerOpen {
            self = answers.hasAnswered ? .delivery : .taskTurn
        } else if answers.hasAnswered {
            self = .waitingForChildren
        } else {
            self = current
        }
    }
}

/// The run that calls the `agents` tool, as the tool sees it
/// (plan.md §9.3, children and depth).
///
/// `start agent` uses it to give a child its depth and its inherited slot,
/// and the child adds itself to ``children``. A root session that is not a
/// run has no such value.
struct ParentRun: Sendable {
    /// The children of one run. The run makes them before its session,
    /// because the `agents` tool of the session needs them.
    struct Family: Sendable {
        /// The runs that the run starts.
        let children = AgentRunChildren()
    }

    /// The depth of the calling run. A host-started run has depth one.
    let depth: Int

    /// The slot of the session of the calling run.
    let slot: ModelSlot

    /// The children of the calling run.
    let family: Family

    /// The runs that the calling run started.
    var children: AgentRunChildren {
        family.children
    }
}

/// The runs that one run started (plan.md §9.3, children).
///
/// A child adds itself before its answers start. The run finishes only after
/// each child ended and its final message was answered.
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

    /// The list and its closed flag.
    private let storage = Mutex(Storage())

    /// Makes an empty list.
    init() {}

    /// The runs that the parent started, in start order.
    var runs: [AgentRun] {
        storage.withLock { $0.runs }
    }

    /// The count of children that did not end.
    var openCount: Int {
        storage.withLock { storage in storage.runs.count(where: { $0.state == .running }) }
    }

    /// Adds a child that is about to start its answers.
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
    /// The sentence that `check agent` adds after the answer of the task
    /// prompt while children are open: "It waits for `N` agents that it
    /// started." `nil` in the answer of the task prompt, or when no child is
    /// open.
    var waitingSentence: String? {
        let open = children.openCount
        guard phase != .taskTurn, open > 0 else {
            return nil
        }
        return "It waits for \(open) agents that it started."
    }
}
