import Foundation
import FoundationModelsRouter
import Synchronization
import ULID

/// One delegated task: one agent, one prompt, and one Router session
/// (plan.md §8, §8.1).
///
/// `start` does the synchronous steps before it returns: it renders the
/// body, puts the instructions in order, makes the tools, matches the model,
/// and makes the session. Thus ``id`` is the session id at once. Only the
/// turn runs in the background, and nothing goes to the caller during the
/// turn. The text of the last turn is the result. The run then closes its
/// session, and a finished run holds no session.
///
/// A run whose setup fails has no session. It gets a new ULID, no recording
/// directory, and the state ``AgentRunState/failed(_:)``.
///
/// A class, because the runner and the caller share one run. A `Mutex`
/// guards the state, thus the `Sendable` conformance is compiler-checked.
public final class AgentRun: Sendable {
    /// The state that the lock guards.
    private struct Storage {
        /// The state of the run.
        var state: AgentRunState

        /// The session of the run until the turn ends, then `nil`.
        var session: (any RoutedSession)?

        /// The background task of the turn, or `nil` for a run whose setup
        /// failed. It gives the final state of the run.
        var turn: Task<AgentRunState, Never>?

        /// The live progress of the run: its phase, its passes, its last
        /// tool calls, and the tail of its text.
        var progress = AgentRunProgress()

        /// The final state of the run from the time that its turns end, or
        /// `nil` before that time. ``state`` stays
        /// ``AgentRunState/running`` until the run cancels its children,
        /// closes its session, and posts. A cancel reads this value.
        var settled: AgentRunState?
    }

    /// The id of the run. It is the session id and the name of the
    /// recording directory. A run whose setup failed has a new ULID.
    public let id: ULID

    /// The resolved agent. The run keeps it for its whole life.
    public let agent: AgentDefinition

    /// The session of the caller, or `nil` for a host-driven run.
    public let caller: ULID?

    /// The depth of the run. A host-started run has depth one.
    public let depth: Int

    /// The directory of the recording of the session:
    /// `<recordingsDir>/<routerId>/<id>`. It is `nil` for a run whose setup
    /// failed.
    public let recordingDirectory: URL?

    /// The slot of the session, or `nil` for a run whose setup failed.
    let slot: ModelSlot?

    /// The context of the tool call that started the run, or `nil` for a
    /// host-driven run. The run posts its final message through it
    /// (plan.md §9.2).
    let context: ToolContext?

    /// The run that started this run with its `agents` tool, or `nil` when
    /// the caller is not a run. The run tells it when the run ends.
    let parent: ParentRun?

    /// The runs that this run started. The run finishes only after each of
    /// them ends (plan.md §9.3, children).
    let children: AgentRunChildren

    /// The count of the passes of the control loop over all the turns of
    /// the run, and the `maxTurns` limit of the agent (plan.md §5).
    let turns: AgentRunTurns

    /// The mutable state of the run.
    private let storage: Mutex<Storage>

    /// `true` when the setup of the run failed: the run made no session and
    /// ran no turn. Its state is ``AgentRunState/failed(_:)`` from the start.
    var isSetupFailure: Bool {
        slot == nil
    }

    /// The state of the run.
    public var state: AgentRunState {
        storage.withLock { $0.state }
    }

    /// The session that the run holds: the session of the turn in operation,
    /// or `nil` after the turn ends. The run never gives the session to the
    /// caller.
    var heldSession: (any RoutedSession)? {
        storage.withLock { $0.session }
    }

    /// The live progress of the run, with the pass count of ``turns``. A
    /// read takes only the locks of the run, thus it never waits for the
    /// turn.
    var progress: AgentRunProgress {
        var progress = storage.withLock { $0.progress }
        progress.passes = turns.count
        return progress
    }

    /// The part of the life of the run after its setup.
    var phase: AgentRunPhase {
        storage.withLock { $0.progress.phase }
    }

    /// `true` when the run holds a place in the run limit: it is in
    /// operation and does not wait for its children (plan.md §9.3).
    var isWorking: Bool {
        storage.withLock { storage in
            storage.state == .running && storage.progress.phase != .waitingForChildren
        }
    }

    /// Makes a run.
    ///
    /// - Parameters:
    ///   - id: The id of the run.
    ///   - request: The inputs of the run.
    ///   - made: The session and its slot, or `nil` when the setup failed.
    ///   - children: The list of the runs that this run starts.
    ///   - state: The first state of the run.
    private init(
        id: ULID, request: AgentRunRequest, made: AgentSessionMaker.Made?, children: AgentRunChildren,
        state: AgentRunState
    ) {
        self.id = id
        self.agent = request.definition
        self.caller = request.context?.sessionID
        self.depth = request.depth
        self.recordingDirectory = made?.session.recordingDirectory
        self.slot = made?.slot
        self.context = request.context
        self.parent = request.parent
        self.children = children
        self.turns = AgentRunTurns(limit: request.definition.maxTurns)
        self.storage = Mutex(Storage(state: state, session: made?.session, turn: nil))
    }

    /// Gives the maker of the `agents` tool of each run that `runner`
    /// starts (plan.md §8 step 4, §9.3).
    ///
    /// The tool of a run is new for each run. `Agent(a, b)` limits it to
    /// the names `a` and `b`. The tool knows the run as its ``ParentRun``,
    /// thus each run that it starts has this run as its caller, the depth of
    /// this run plus one, and the slot of this run for `model: inherit`.
    ///
    /// - Parameter runner: The runner that owns each run that the tool
    ///   starts.
    /// - Returns: The maker.
    static func agentsTool(of runner: AgentRunner) -> AgentRunRequest.AgentsToolMaker {
        { parent, allowedNames in
            try await AgentsTool.make(
                context: AgentsToolContext(runner: runner, allowedNames: allowedNames, parent: parent))
        }
    }

    /// Starts the run of `request` (plan.md §8).
    ///
    /// The setup is done when the call returns, thus the run has its id.
    /// A run whose caller is a run adds itself to the children of that run
    /// before its turn starts. The turn then runs in the background.
    ///
    /// - Parameters:
    ///   - request: The inputs of the run.
    ///   - environment: The dependencies and the limits of the runs.
    ///   - renderer: Renders the body of the agent.
    /// - Returns: The run, in ``AgentRunState/running``, or in
    ///   ``AgentRunState/failed(_:)`` when the setup failed.
    static func start(
        _ request: AgentRunRequest, environment: AgentEnvironment, renderer: AgentBodyRenderer
    ) async -> AgentRun {
        let children = AgentRunChildren()
        let made: AgentSessionMaker.Made
        do {
            made = try await AgentSessionMaker(environment: environment, renderer: renderer)
                .makeSession(for: request, children: children)
        } catch {
            return AgentRun(id: ULID(), request: request, made: nil, children: children, state: .failed(error))
        }
        let run = AgentRun(id: made.session.id, request: request, made: made, children: children, state: .running)
        let isAdopted = request.parent?.children.add(run) ?? true
        run.startTurn(on: made.session, prompt: request.prompt)
        if !isAdopted {
            run.cancel()
        }
        return run
    }

    /// Waits for the run to end, and gives its result.
    ///
    /// A cancel of the task that waits cancels the run (``cancel()``). The
    /// call then throws `CancellationError` when the run ends as cancelled.
    /// A run that ended before the cancel gives its result as usual.
    ///
    /// - Returns: The text of the last turn.
    /// - Throws: The ``AgentRunFailure`` of a failed run, or
    ///   `CancellationError` for a cancelled run.
    public func result() async throws -> String {
        let final = await withTaskCancellationHandler {
            await finalState()
        } onCancel: {
            cancel()
        }
        switch final {
        case .finished(let text):
            return text
        case .failed(let failure):
            throw failure
        case .cancelled, .running:
            throw CancellationError()
        }
    }

    /// Waits for the run to end, and gives its final state. It does not throw
    /// for a failed or a cancelled run.
    ///
    /// - Returns: The final state of the run. The session is closed when the
    ///   call returns.
    func finalState() async -> AgentRunState {
        let turn = storage.withLock { $0.turn }
        return await turn?.value ?? state
    }

    /// Cancels the turn of the run and the runs that it started. The run
    /// cancels its open children and waits for them, then closes its session,
    /// posts its final message, and goes to ``AgentRunState/cancelled``. A
    /// run that ended stays as it is.
    public func cancel() {
        storage.withLock { $0.turn }?.cancel()
    }

    /// Cancels the run, and tells what the cancel did (plan.md §9.1,
    /// `cancel agent`).
    ///
    /// The final state of a run is known when its turns end, before it
    /// cancels its children, closes its session, and posts. A cancel from
    /// that time on changes nothing, thus it tells the known final state.
    ///
    /// - Returns: ``CancelOutcome/reported(_:)`` with `.cancelled` when the
    ///   final state was not known: the cancel is sent, and the run stops
    ///   when its turn unwinds. ``CancelOutcome/alreadySettled(_:)`` with
    ///   the final message of the known final state when the run had ended
    ///   before the cancel.
    func requestCancel() -> CancelOutcome {
        let known = storage.withLock { storage in
            storage.settled ?? (storage.state == .running ? nil : storage.state)
        }
        guard let known, let finalMessage = finalMessage(for: known) else {
            cancel()
            return .reported(.cancelled)
        }
        return .alreadySettled(finalMessage)
    }

    /// Starts the background task that drives the turns of the run.
    ///
    /// The task is detached, thus it does not take the `ToolContext` of the
    /// tool call that started the run. The tools of the session bind their
    /// own contexts.
    ///
    /// Before the task turn, the task subscribes to the session events. A
    /// child task reads that one subscription for the whole run
    /// (``followPasses(_:on:)``): it counts the passes of each turn and feeds
    /// the progress.
    ///
    /// When the last turn ends, the task records the settled final state
    /// (``settle(_:)``) at once. It then cancels the open children and waits
    /// for them (a cancel or a failure can leave children open), and closes
    /// the session. The close finishes the subscription, thus the child task
    /// ends. The task then posts the final message, records the final state,
    /// and tells the parent run. Thus a caller that sees the final state
    /// knows that the post is done, and that no task of the run stays.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - prompt: The prompt of the task turn.
    private func startTurn(on session: any RoutedSession, prompt: String) {
        let turn = Task.detached {
            let events = await session.streamSessionEvents()
            let final = await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.followPasses(events, on: session) }
                let final = self.settle(await self.drive(session, prompt: prompt))
                await self.children.cancelOpenRuns()
                await session.close()
                return final
            }
            await self.postFinalMessage(for: final)
            self.end(in: final)
            self.parent?.children.childDidEnd()
            return final
        }
        storage.withLock { $0.turn = turn }
    }

    /// Records the part of the life of the run that starts now.
    ///
    /// - Parameter phase: The new phase.
    func enter(_ phase: AgentRunPhase) {
        storage.withLock { $0.progress.phase = phase }
    }

    /// Adds one event of a turn to the progress of the run.
    ///
    /// - Parameter event: An event of the session-event subscription of the
    ///   run, or a text event of the task turn.
    func record(_ event: SessionEvent) {
        storage.withLock { $0.progress.apply(event) }
    }

    /// Sets the text tail of the progress to the text of a delivery turn or
    /// a final-answer turn. The session events of these turns carry no text,
    /// thus the tail changes only when the turn returns.
    ///
    /// - Parameter text: The text that the turn gave.
    func recordDelivered(_ text: String) {
        storage.withLock { $0.progress.replaceText(with: text) }
    }

    /// Records the final state of the run when its turns end. From this time
    /// on, ``requestCancel()`` tells this state.
    ///
    /// - Parameter final: The final state that the turns gave.
    /// - Returns: `final`.
    private func settle(_ final: AgentRunState) -> AgentRunState {
        storage.withLock { $0.settled = final }
        return final
    }

    /// Records the final state, and lets go of the session.
    ///
    /// - Parameter final: The final state of the run.
    private func end(in final: AgentRunState) {
        storage.withLock { storage in
            storage.state = final
            storage.session = nil
        }
    }

    /// Drives the task turn with `prompt` (``runTaskTurn(on:prompt:)``).
    /// Then delivers the final messages of the children in delivery turns,
    /// and runs a final-answer turn after them
    /// (``finishAfterChildren(on:taskTurnText:)``).
    ///
    /// When the count goes above the `maxTurns` limit, the run cancels its
    /// turn, and fails with ``AgentRunFailure/hitMaxTurns(partial:)``, not
    /// as cancelled.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - prompt: The prompt of the task turn.
    /// - Returns: The final state: ``AgentRunState/finished(_:)`` with the
    ///   text of the last turn, ``AgentRunState/cancelled`` for a cancelled
    ///   run, or ``AgentRunState/failed(_:)`` for an error of a turn or for
    ///   a count above the `maxTurns` limit.
    private func drive(_ session: any RoutedSession, prompt: String) async -> AgentRunState {
        do {
            let taskTurnText = try await runTaskTurn(on: session, prompt: prompt)
            let result = try await finishAfterChildren(on: session, taskTurnText: taskTurnText)
            return Task.isCancelled ? .cancelled : .finished(result)
        } catch {
            return Task.isCancelled || error is CancellationError
                ? .cancelled : .failed(AgentRunFailure.turnFailure(for: error))
        }
    }
}
