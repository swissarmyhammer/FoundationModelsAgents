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
/// answers run in the background, and nothing goes to the caller while they
/// run. The run ends when its session is idle, and the reply of the last
/// answer is the result. The run then closes its session, and a finished run
/// holds no session.
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

        /// The session of the run until its answers end, then `nil`.
        var session: (any RoutedSession)?

        /// The background task that drives the session, or `nil` for a run
        /// whose setup failed. It gives the final state of the run.
        var driver: Task<AgentRunState, Never>?

        /// The live progress of the run: its phase, its last tool calls, and
        /// the tail of its text.
        var progress = AgentRunProgress()

        /// The answers of the session so far.
        var answers = AgentRunAnswers()

        /// `true` after a caller cancelled the run.
        var isCancelRequested = false

        /// The final state of the run from the time that its answers end, or
        /// `nil` before that time. ``state`` stays
        /// ``AgentRunState/running`` until the run cancels its children and
        /// closes its session. A cancel reads this value.
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
    /// host-driven run. It gives the lineage of the session (plan.md §8.2).
    let context: ToolContext?

    /// The runs that this run started. The run finishes only after each of
    /// them ends and its final message was answered (plan.md §9.3,
    /// children).
    let children: AgentRunChildren

    /// The watch of the session of the run. The follower of the run feeds
    /// it, and the run waits on it before it closes its session.
    let sessionWatch = ParentSessionWatch()

    /// The count of the passes of the control loop over all the answers of
    /// the run, and the `maxTurns` limit of the agent (plan.md §5).
    let turns: AgentRunTurns

    /// The signals that decide the end of the run.
    let signals = AgentRunSignals()

    /// The mutable state of the run.
    private let storage: Mutex<Storage>

    /// `true` when the setup of the run failed: the run made no session and
    /// ran no answer. Its state is ``AgentRunState/failed(_:)`` from the
    /// start.
    var isSetupFailure: Bool {
        slot == nil
    }

    /// The id of the session of the run. It is equal to ``id``, or `nil` for a
    /// run whose setup failed, because that run has no session. Use it, not
    /// ``id``, when you compare the run with a session id, for example the
    /// `sessionID` of a `ToolContext`.
    var sessionID: ULID? {
        isSetupFailure ? nil : id
    }

    /// The state of the run.
    public var state: AgentRunState {
        storage.withLock { $0.state }
    }

    /// The session that the run holds: the session of the answers in
    /// operation, or `nil` after the answers end. The run never gives the
    /// session to the caller.
    var heldSession: (any RoutedSession)? {
        storage.withLock { $0.session }
    }

    /// The live progress of the run, with the pass count of ``turns``. A
    /// read takes only the locks of the run, thus it never waits for an
    /// answer.
    var progress: AgentRunProgress {
        var progress = storage.withLock { $0.progress }
        progress.passes = turns.count
        return progress
    }

    /// The part of the life of the run after its setup.
    var phase: AgentRunPhase {
        storage.withLock { $0.progress.phase }
    }

    /// The answers of the session of the run so far.
    var answers: AgentRunAnswers {
        storage.withLock { $0.answers }
    }

    /// `true` after a caller cancelled the run.
    var isCancelRequested: Bool {
        storage.withLock { $0.isCancelRequested }
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
    ///   - family: The children of the run.
    ///   - state: The first state of the run.
    private init(
        id: ULID, request: AgentRunRequest, made: AgentSessionMaker.Made?, family: ParentRun.Family,
        state: AgentRunState
    ) {
        self.id = id
        self.agent = request.definition
        self.caller = request.context?.sessionID
        self.depth = request.depth
        self.recordingDirectory = made?.session.recordingDirectory
        self.slot = made?.slot
        self.context = request.context
        self.children = family.children
        self.turns = AgentRunTurns(limit: request.definition.maxTurns)
        self.storage = Mutex(Storage(state: state, session: made?.session, driver: nil))
    }

    /// Gives the maker of the `agents` tool of each run that `runner`
    /// starts (plan.md §8 step 4, §9.3).
    ///
    /// A run uses the maker only when its `tools` key has an `Agent`,
    /// `Agent(a, b)`, or `agents` entry. The tool of a run is new for each
    /// run. `Agent(a, b)` limits it to the names `a` and `b`. The tool
    /// knows the run as its ``ParentRun``, thus each run that it starts has
    /// this run as its caller, the depth of this run plus one, and the slot
    /// of this run for `model: inherit`.
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
    /// before its answers start. The answers then run in the background.
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
        let family = ParentRun.Family()
        let made: AgentSessionMaker.Made
        do {
            made = try await AgentSessionMaker(environment: environment, renderer: renderer)
                .makeSession(for: request, family: family)
        } catch {
            return AgentRun(id: ULID(), request: request, made: nil, family: family, state: .failed(error))
        }
        let run = AgentRun(id: made.session.id, request: request, made: made, family: family, state: .running)
        let isAdopted = request.parent?.children.add(run) ?? true
        run.startDriver(on: made.session, prompt: request.prompt)
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
    /// - Returns: The reply of the last answer of the run.
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
        let driver = storage.withLock { $0.driver }
        return await driver?.value ?? state
    }

    /// Cancels the answers of the run and the runs that it started. The run
    /// stops its session, cancels its open children and waits for them, then
    /// closes its session and goes to ``AgentRunState/cancelled``. A run that
    /// ended stays as it is.
    ///
    /// The cancel is a signal to the task that drives the run, not a cancel
    /// of that task. Thus the task still reads the session events while it
    /// stops the session and waits for the children.
    public func cancel() {
        storage.withLock { $0.isCancelRequested = true }
        signals.continuation.yield(.cancelRequested)
    }

    /// Cancels the run, and tells what the cancel did (plan.md §9.1,
    /// `cancel agent`).
    ///
    /// The final state of a run is known when its answers end, before it
    /// cancels its children and closes its session. A cancel from that time
    /// on changes nothing, thus it tells the known final state.
    ///
    /// - Returns: ``CancelOutcome/reported(_:)`` with `.cancelled` when the
    ///   final state was not known: the cancel is sent, and the run stops
    ///   when its answer unwinds. ``CancelOutcome/alreadySettled(_:)`` with
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

    /// Starts the background task that drives the session of the run
    /// (``drive(_:prompt:)``).
    ///
    /// The task is detached, thus it does not take the `ToolContext` of the
    /// tool call that started the run. The tools of the session bind their
    /// own contexts.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - prompt: The task prompt.
    private func startDriver(on session: any RoutedSession, prompt: String) {
        let driver = Task.detached {
            let final = await self.drive(session, prompt: prompt)
            self.end(in: final)
            return final
        }
        storage.withLock { $0.driver = driver }
    }

    /// Adds one event of the session to the record of the run: its progress,
    /// its answers, and its phase.
    ///
    /// - Parameter event: An event of the session-event subscription.
    func record(_ event: SessionEvent) {
        storage.withLock { storage in
            storage.progress.apply(event)
            storage.answers.apply(event)
            storage.progress.phase = AgentRunPhase(after: storage.answers, current: storage.progress.phase)
        }
    }

    /// Records the final state of the run when its answers end. From this
    /// time on, ``requestCancel()`` tells this state.
    ///
    /// - Parameter final: The final state that the answers gave.
    /// - Returns: `final`.
    func settle(_ final: AgentRunState) -> AgentRunState {
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
}
