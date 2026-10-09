import Foundation
import FoundationModelsRouter
import Synchronization
import Tracing
import ULID

/// One delegated task: one agent, one prompt, and one Router session.
///
/// `make` does the synchronous steps before it returns: it renders the
/// body, puts the instructions in order, makes the tools, matches the model,
/// and makes the session. Thus ``id`` is the session id at once. Only the
/// answers run in the background from `begin`, and nothing goes to the
/// caller while they run. The run ends when its session is idle, and the
/// reply of the last answer is the result. The run then closes its session,
/// and a finished run holds no session.
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

        /// The count of messages from the caller that ``AgentRun/deliver(_:)``
        /// accepted and did not yet put in the message queue of the session.
        /// A held message (``callerMessages``) is in this count.
        var inboundMessages = 0

        /// The gate of the messages from the caller. It holds each message
        /// until the run reads the start of the answer of its task prompt.
        var callerMessages = CallerMessageGate.holding([])

        /// The count of all messages from the caller that
        /// ``AgentRun/deliver(_:)`` accepted. It only goes up. An idle check
        /// records it, and the run ends on that check only when the count
        /// did not change after it (``AgentRun/settle(idle:acceptedMessages:)``).
        var acceptedMessages = 0

        /// The test hooks of the idle rule. They do nothing in a run that no
        /// test changes.
        var idleHooks = AgentRunIdleHooks()
    }

    /// The gate of the messages from the caller of the run.
    ///
    /// The task prompt is the first message of the session. `begin` starts
    /// the task that sends it, and returns before that task sends it. Thus a
    /// message from the caller that goes to the session before the run reads
    /// the start of the answer of the task prompt can come before the task
    /// prompt. The run holds each such message, and sends it after that
    /// start (``AgentRun/releaseHeldMessages(to:)``).
    private enum CallerMessageGate {
        /// The run holds these messages, in the order that they arrived. The
        /// run did not read the start of the answer of its task prompt, or it
        /// did not yet send each held message.
        case holding([String])

        /// The run sent each held message. A new message goes to the session
        /// at once.
        case open
    }

    /// What ``AgentRun/deliver(_:)`` does with one message from the caller.
    private enum MessageAdmission {
        /// Send the message to this session now.
        case send(any RoutedSession)

        /// The run holds the message, and sends it later.
        case held

        /// The run does not accept the message: it started to end in this
        /// state.
        case ended(AgentRunState)
    }

    /// The id of the run. It is the session id and the name of the
    /// recording directory. A run whose setup failed has a new ULID.
    public let id: ULID

    /// The resolved agent. The run keeps it for its whole life.
    public let agent: AgentDefinition

    /// The session of the caller, or `nil` for a host-driven run.
    public let caller: ULID?

    /// The id of the run that started this run: the session of the caller
    /// when the caller is a run, or `nil` when the host or a session that is
    /// not a run started this run. The session of a run has the id of the
    /// run.
    let parentRunID: ULID?

    /// The depth of the run. A host-started run has depth one.
    public let depth: Int

    /// The directory of the recording of the session:
    /// `<recordingsDir>/<routerId>/<id>`. It is `nil` for a run whose setup
    /// failed.
    public let recordingDirectory: URL?

    /// The slot of the session, or `nil` for a run whose setup failed.
    let slot: ModelSlot?

    /// The context of the tool call that started the run, or `nil` for a
    /// host-driven run. It gives the lineage of the session.
    let context: ToolContext?

    /// The runs that this run started. The run finishes only after each of
    /// them ends and its final message was answered.
    let children: AgentRunChildren

    /// The watch of the session of the run. The follower of the run feeds
    /// it, and the run waits on it before it closes its session.
    let sessionWatch = ParentSessionWatch()

    /// The count of the passes of the control loop over all the answers of
    /// the run, and the `maxTurns` limit of the agent.
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

    /// The test hooks of the idle rule of the run.
    var idleHooks: AgentRunIdleHooks {
        storage.withLock { $0.idleHooks }
    }

    /// `true` when the run holds a place in the run limit: it is in
    /// operation and does not wait for its children.
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
        self.parentRunID = request.parent == nil ? nil : request.context?.sessionID
        self.depth = request.depth
        self.recordingDirectory = made?.session.recordingDirectory
        self.slot = made?.slot
        self.context = request.context
        self.children = family.children
        self.turns = AgentRunTurns(limit: request.definition.maxTurns)
        self.storage = Mutex(Storage(state: state, session: made?.session, driver: nil))
    }

    /// Gives the maker of the `agents` tool of each run that `runner` starts.
    ///
    /// A run uses the maker only when its `tools` key has an `Agent`,
    /// `Agent(a, b)`, or `agents` entry. The tool of a run is new for each
    /// run. `Agent(a, b)` limits it to the names `a` and `b`. The tool
    /// knows the run as its ``ParentRun``, thus each run that it starts has
    /// this run as its caller, the depth of this run plus one, and the slot
    /// of this run for `model: inherit`. The tool also keeps the link to the
    /// caller of this run, and gives the operations of its grant.
    ///
    /// - Parameter runner: The runner that owns each run that the tool
    ///   starts.
    /// - Returns: The maker.
    static func agentsTool(of runner: AgentRunner) -> AgentRunRequest.AgentsToolMaker {
        { parent, callerLink, grant, allowedNames in
            try await AgentsTool.make(
                context: AgentsToolContext(
                    runner: runner, allowedNames: allowedNames, parent: parent, callerLink: callerLink, grant: grant))
        }
    }

    /// Makes the run of `request`: the setup, and no answer.
    ///
    /// The setup is done when the call returns, thus the run has its id. The
    /// session gets no prompt until ``begin(_:environment:)``. Thus the runner
    /// can put the run in its index before the session can call a tool. A
    /// message from the caller before that time waits in the run
    /// (``deliver(_:)``).
    ///
    /// Each run has one span and its log records (``traced(in:_:)``), a child
    /// of the `ServiceContext` of the caller. The span and the records of a
    /// run whose setup failed start and end in this call.
    ///
    /// - Parameters:
    ///   - request: The inputs of the run.
    ///   - environment: The dependencies and the limits of the runs.
    ///   - renderer: Renders the body of the agent.
    /// - Returns: The run, in ``AgentRunState/running``, or in
    ///   ``AgentRunState/failed(_:)`` when the setup failed.
    internal static func make(
        _ request: AgentRunRequest, environment: AgentEnvironment, renderer: AgentBodyRenderer
    ) async -> AgentRun {
        let family = ParentRun.Family()
        let made: AgentSessionMaker.Made
        do {
            made = try await AgentSessionMaker(environment: environment, renderer: renderer)
                .makeSession(for: request, family: family)
        } catch {
            let run = AgentRun(id: ULID(), request: request, made: nil, family: family, state: .failed(error))
            _ = await run.traced(in: environment) { _ in run.state }
            return run
        }
        return AgentRun(id: made.session.id, request: request, made: made, family: family, state: .running)
    }

    /// Begins the answers of a run that ``make(_:environment:renderer:)``
    /// gave. Call it one time for each run.
    ///
    /// A run whose caller is a run adds itself to the children of that run
    /// before its answers start. The answers then run in the background. A
    /// run whose setup failed has no session, thus the call does nothing.
    ///
    /// - Parameters:
    ///   - request: The inputs of the run: the request of `make`.
    ///   - environment: The dependencies and the limits of the runs.
    internal func begin(_ request: AgentRunRequest, environment: AgentEnvironment) {
        guard let session = heldSession else { return }
        let isAdopted = request.parent?.children.add(self) ?? true
        startDriver(on: session, prompt: request.prompt, environment: environment)
        if !isAdopted {
            cancel()
        }
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

    /// Cancels the run, and tells what the cancel did (`cancel agent`).
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

    /// Sends a message from the caller to the session of the run, or tells
    /// that the run ended.
    ///
    /// The run accepts the message while it is in operation: in the turn of
    /// its task prompt, and while it waits for its children. The session
    /// then answers the message before the run ends, because a message that
    /// the run accepted keeps it from the idle end
    /// (``acceptedMessagesIfIdle(on:)``, ``settle(idle:acceptedMessages:)``). The
    /// prompt of the message is ``AgentsToolText/callerMessage(_:)``.
    ///
    /// The task prompt is always the first message of the session. Before
    /// ``begin(_:environment:)``, and after it until the run reads the start
    /// of the answer of the task prompt, the run holds the message
    /// (``CallerMessageGate``). The run then sends each held message, in
    /// order (``releaseHeldMessages(to:)``). A held message keeps the run
    /// from the idle end as a message on its way to the queue does. A run
    /// that is cancelled or fails before that start does not send its held
    /// messages.
    ///
    /// The answer of a message to a run that waits for its children starts
    /// with no check against ``AgentEnvironment/maxConcurrentAgents``. An
    /// answer to the final message of a child does the same.
    ///
    /// - Parameter message: The text of the caller.
    /// - Returns: ``AgentRunMessageOutcome/delivered`` when the run accepted
    ///   the message: the session got it, or the run holds it.
    ///   ``AgentRunMessageOutcome/ended(_:)`` with the final state when the
    ///   run started to end before the message: its answers ended, a caller
    ///   cancelled it, or its setup failed.
    func deliver(_ message: String) async -> AgentRunMessageOutcome {
        let admission = storage.withLock { storage in
            Self.admit(message, in: &storage)
        }
        switch admission {
        case .send(let session):
            await send(message, to: session)
            return .delivered
        case .held:
            return .delivered
        case .ended(let state):
            return .ended(state)
        }
    }

    /// Sends each message that ``deliver(_:)`` held, in order, and then
    /// opens the gate (``CallerMessageGate/open``). The follower of the run
    /// calls it when it reads the start of an answer. The first start is the
    /// start of the answer of the task prompt, thus each held message goes
    /// to the session after the task prompt. A message that arrives while
    /// this call sends is held too, and this call sends it, thus the order
    /// of the messages stays. After the gate opens, the call does nothing.
    ///
    /// - Parameter session: The session of the run.
    func releaseHeldMessages(to session: any RoutedSession) async {
        while let message = storage.withLock({ Self.takeHeldMessage(from: &$0) }) {
            await send(message, to: session)
        }
    }

    /// Decides what ``deliver(_:)`` does with `message`, under the lock of
    /// the run.
    ///
    /// - Parameters:
    ///   - message: The text of the caller.
    ///   - storage: The state of the run. An accepted message goes in the
    ///     counts, and a held message goes in the gate.
    /// - Returns: The admission of the message.
    private static func admit(_ message: String, in storage: inout Storage) -> MessageAdmission {
        if let settled = storage.settled {
            return .ended(settled)
        }
        if storage.isCancelRequested {
            return .ended(.cancelled)
        }
        guard let session = storage.session else {
            return .ended(storage.state)
        }
        storage.inboundMessages += 1
        storage.acceptedMessages += 1
        guard case .holding(let held) = storage.callerMessages else {
            return .send(session)
        }
        storage.callerMessages = .holding(held + [message])
        return .held
    }

    /// Takes the first held message from the gate, under the lock of the
    /// run. When no message is held, the gate opens.
    ///
    /// - Parameter storage: The state of the run.
    /// - Returns: The first held message, or `nil` when the gate is open.
    private static func takeHeldMessage(from storage: inout Storage) -> String? {
        guard case .holding(let held) = storage.callerMessages else {
            return nil
        }
        guard let first = held.first else {
            storage.callerMessages = .open
            return nil
        }
        storage.callerMessages = .holding(Array(held.dropFirst()))
        return first
    }

    /// Puts one accepted message from the caller in the message queue of the
    /// session, and removes it from the count of inbound messages.
    ///
    /// - Parameters:
    ///   - message: The text of the caller.
    ///   - session: The session of the run.
    private func send(_ message: String, to session: any RoutedSession) async {
        await session.send(AgentsToolText.callerMessage(message))
        storage.withLock { $0.inboundMessages -= 1 }
    }

    /// Sets the test hooks of the idle rule of the run. Call it before
    /// ``begin(_:environment:)``.
    ///
    /// - Parameter hooks: The hooks.
    func install(_ hooks: AgentRunIdleHooks) {
        storage.withLock { $0.idleHooks = hooks }
    }

    /// Starts the background task that holds the span and the log records of
    /// the run (``traced(in:_:)``), and in it the task that drives the session
    /// of the run (``drive(_:prompt:)``).
    ///
    /// The task of the span is not detached: it takes the task-local values
    /// of the caller. Thus the span is a child of the `ServiceContext` of the
    /// caller, and the log records go to the log capture of the caller when
    /// the environment gives no logger.
    /// The task that drives the session is detached, thus it does not take
    /// the `ToolContext` of the tool call that started the run. The tools of
    /// the session bind their own contexts. That task binds the context of
    /// the span, thus the session gets it when the run sends its task prompt,
    /// and the Router opens the submission spans of that prompt as children
    /// of the span of the run.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - prompt: The task prompt.
    ///   - environment: The environment of the run. It gives the tracer of
    ///     the span and the logger of the records.
    private func startDriver(on session: any RoutedSession, prompt: String, environment: AgentEnvironment) {
        let driver = Task {
            await self.traced(in: environment) { spanContext in
                let final = await Task.detached {
                    await ServiceContext.withValue(spanContext) {
                        await self.drive(session, prompt: prompt)
                    }
                }.value
                self.end(in: final)
                return final
            }
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

    /// The count of messages that ``deliver(_:)`` accepted, for the start of
    /// an idle check, or `nil` while a message is on its way to the message
    /// queue of the session. The session is not idle then.
    var acceptedMessagesWhenNoneInbound: Int? {
        storage.withLock { storage in
            storage.inboundMessages == 0 ? storage.acceptedMessages : nil
        }
    }

    /// Records the final state of an idle run, when no message from the
    /// caller arrived after the idle check. One lock holds the check and the
    /// record, thus ``deliver(_:)`` accepts each message before this call,
    /// and the run then answers it, or refuses it after this call.
    ///
    /// - Parameters:
    ///   - final: The final state that the idle signal gave.
    ///   - acceptedMessages: The count of accepted messages that the idle
    ///     check read.
    /// - Returns: `final`, or `nil` when ``deliver(_:)`` accepted a message
    ///   after the idle check. The run then waits for its answer.
    func settle(idle final: AgentRunState, acceptedMessages: Int) -> AgentRunState? {
        storage.withLock { storage in
            guard storage.inboundMessages == 0, storage.acceptedMessages == acceptedMessages else {
                return nil
            }
            storage.settled = final
            return final
        }
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
