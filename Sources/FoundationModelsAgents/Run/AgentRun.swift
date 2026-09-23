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

        /// The phrase of the last event of the turn that tells a kind of
        /// work (``AgentRunActivity``).
        var lastEvent = AgentRunActivity.started

        /// The part of the life of the run after its setup.
        var phase = AgentRunPhase.taskTurn
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

    /// The phrase of the last event of the turn that tells a kind of work,
    /// for example "it called the tool Read". It is
    /// ``AgentRunActivity/started`` until the turn gives such an event.
    var lastEvent: String {
        storage.withLock { $0.lastEvent }
    }

    /// The part of the life of the run after its setup.
    var phase: AgentRunPhase {
        storage.withLock { $0.phase }
    }

    /// `true` when the run holds a place in the run limit: it is in
    /// operation and does not wait for its children (plan.md §9.3).
    var isWorking: Bool {
        storage.withLock { storage in storage.state == .running && storage.phase != .waitingForChildren }
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
    /// - Returns: The text of the last turn.
    /// - Throws: The ``AgentRunFailure`` of a failed run, or
    ///   `CancellationError` for a cancelled run.
    public func result() async throws -> String {
        switch await finalState() {
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
    /// - Returns: ``CancelOutcome/reported(_:)`` with `.cancelled` when the
    ///   run was in operation: the cancel is sent, and the run stops when its
    ///   turn unwinds. ``CancelOutcome/alreadySettled(_:)`` with the final
    ///   message when the run had ended before the cancel.
    func requestCancel() -> CancelOutcome {
        guard let finalMessage = finalMessage(for: state) else {
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
    /// When the last turn ends, the task cancels the open children and waits
    /// for them (a cancel or a failure can leave children open), closes the
    /// session, posts the final message, records the final state, and then
    /// tells the parent run. Thus a caller that sees the final state knows
    /// that the post is done.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - prompt: The prompt of the task turn.
    private func startTurn(on session: any RoutedSession, prompt: String) {
        let turn = Task.detached {
            let final = await self.drive(session, prompt: prompt)
            await self.children.cancelOpenRuns()
            await session.close()
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
        storage.withLock { $0.phase = phase }
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

    /// Records the phrase of `event` as ``lastEvent``, when the event tells
    /// a kind of work.
    ///
    /// - Parameter event: An event of the turn.
    private func record(_ event: SessionEvent) {
        guard let phrase = AgentRunActivity.phrase(for: event) else {
            return
        }
        storage.withLock { $0.lastEvent = phrase }
    }

    /// Drives the task turn with `prompt`, collects the text of the answer,
    /// records the last event of work, and adds the passes of the turn to
    /// ``turns``. Then delivers the final messages of the children in
    /// delivery turns (``finishAfterChildren(on:taskTurnText:)``).
    ///
    /// When the count goes above the `maxTurns` limit, the run stops its
    /// read of the turn stream, and that cancels the turn. The run then
    /// fails with ``AgentRunFailure/hitMaxTurns(partial:)``.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - prompt: The prompt of the task turn.
    /// - Returns: The final state: ``AgentRunState/finished(_:)`` with the
    ///   text of the last turn, ``AgentRunState/cancelled`` for a cancelled
    ///   run, or ``AgentRunState/failed(_:)`` for an error of a turn or for
    ///   a count above the `maxTurns` limit.
    private func drive(_ session: any RoutedSession, prompt: String) async -> AgentRunState {
        var text = TurnText()
        do {
            for try await event in await session.streamEvents(to: prompt) {
                text.apply(event)
                record(event)
                try turns.add(event, partial: text.value)
            }
            let result = try await finishAfterChildren(on: session, taskTurnText: text.value)
            return Task.isCancelled ? .cancelled : .finished(result)
        } catch {
            return Task.isCancelled || error is CancellationError
                ? .cancelled : .failed(AgentRunFailure.turnFailure(for: error))
        }
    }
}

/// The text of the answer of one turn, collected from its events.
///
/// A ``SessionEvent/textReset`` clears the text that came before it.
private struct TurnText {
    /// The text so far.
    private(set) var value = ""

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
