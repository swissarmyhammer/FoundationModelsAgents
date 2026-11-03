import Foundation
import FoundationModelsRouter
import ULID

/// The actor that owns each agent run of one host.
///
/// The runner starts runs, keeps the index of the runs, and keeps the records
/// of the finished runs. It is not a session system, a tool loop, a recorder,
/// or a display model. One runner holds one profile: the profile of its
/// environment.
///
/// The init stores its inputs and does no I/O. The runner reads
/// `registry.catalog()` at each call, thus the host calls
/// `AgentRegistry.load()` before the first ``start(_:prompt:)``. Before the
/// load, each ``start(_:prompt:)`` throws
/// ``AgentRunnerError/catalogNotLoaded``. After a
/// `registry.reload()`, a new run uses the new definition.
///
/// ```swift
/// try await agents.load()
/// let runner = AgentRunner(registry: agents, environment: env)
/// async let review = runner.start("code-reviewer", prompt: p1).result()
/// async let tests = runner.start("test-writer", prompt: p2).result()
/// ```
///
/// An ended run moves from the runs in operation to the records at the next
/// call on the runner. ``AgentEnvironment/maxRetainedRuns`` limits the
/// records, and the runner removes the oldest record first.
public actor AgentRunner {
    /// One start whose setup is in operation. The run of such a start is not
    /// in the index yet.
    private struct Setup {
        /// The session of the caller, or `nil` for a host-driven start.
        let caller: ULID?

        /// The cancel calls that wait for the end of the setup.
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    /// The outcome of a start that checks
    /// ``AgentEnvironment/maxConcurrentAgents``.
    enum LimitedStart {
        /// The runner started the run and put it in the index.
        case started(AgentRun)

        /// The limit is full: `working` runs have a turn in operation, and
        /// the runner started no run.
        case atLimit(working: Int)

        /// The host called ``AgentRunner/stop()``, and the runner started no
        /// run.
        case stopped
    }

    /// The depth of a host-started run.
    static let hostDepth = 1

    /// The registry that gives the definitions.
    let registry: AgentRegistry

    /// The dependencies and the limits of the runs.
    let environment: AgentEnvironment

    /// Renders the body of each agent.
    private let renderer: AgentBodyRenderer

    /// The search of `find agents` over the model-visible agents of
    /// ``registry``. It follows each catalog of `onReload`, and it chooses
    /// with ``AgentEnvironment/selectionModel``.
    ///
    /// One search for each runner, thus the tools of the host session and
    /// of each run use one index, and an embedder embeds each catalog one
    /// time.
    let agentSearch: AgentSearch

    /// The runs whose turn can be in operation, by id. Each run holds its
    /// caller, its slot, and its depth.
    var openRuns: [ULID: AgentRun] = [:]

    /// The finished runs, oldest first. Each run holds its id, its agent,
    /// and its final state with the final text.
    var records: [AgentRun] = []

    /// The count of limited starts whose setup is in operation. The actor
    /// can run a second call while a setup waits, thus the limit counts
    /// these starts too.
    private var limitedStartsInSetup = 0

    /// The starts whose setup is in operation, by a key of each start.
    /// ``cancelRuns(caller:)`` and ``stop()`` wait for these setups.
    private var setups: [ULID: Setup] = [:]

    /// `true` after ``stop()``. The runner then starts no run.
    private var isStopped = false

    /// Sends the state changes of the runs to the subscribers of ``runChanges()``.
    let changeHub = RunChangeHub()

    /// Makes a runner. It stores its inputs and does no I/O.
    ///
    /// The init also makes ``agentSearch`` over the current catalog of
    /// `registry`. The search embeds nothing here, and starts one task that
    /// follows `registry.onReload`. Thus a runner made before the first
    /// `registry.load()` gets the catalog of that load.
    ///
    /// - Parameters:
    ///   - registry: The registry that gives the definitions. The host calls
    ///     its `load()` before the first run.
    ///   - environment: The dependencies and the limits of the runs.
    public init(registry: AgentRegistry, environment: AgentEnvironment) {
        self.registry = registry
        self.environment = environment
        self.renderer = AgentBodyRenderer(registry: registry)
        self.agentSearch = AgentSearch(
            registry: registry, selectionModel: environment.selectionModel,
            embedder: ProfileEmbedding(model: environment.profile.embedding))
    }

    /// The runs whose turn is in operation, sorted by id.
    public var runs: [AgentRun] {
        retireEndedRuns()
        return openRuns.values.sorted { $0.id < $1.id }
    }

    /// Starts a host-driven run of the agent `name` in
    /// ``AgentEnvironment/workingDirectory``.
    ///
    /// The call is ``start(_:prompt:workingDirectory:)`` with no folder. Each
    /// agent works in ``AgentEnvironment/workingDirectory``, also an agent of
    /// the agent folder form.
    ///
    /// - Parameters:
    ///   - name: The id of the agent in the catalog of the registry.
    ///   - prompt: The prompt of the run. It is `$ARGUMENTS` of the body and
    ///     the first user prompt of the session.
    /// - Returns: The run. Its setup is done, thus it has its id.
    /// - Throws: The errors of ``start(_:prompt:workingDirectory:)``.
    public func start(_ name: String, prompt: String) async throws(AgentRunnerError) -> AgentRun {
        try await start(name, prompt: prompt, workingDirectory: nil)
    }

    /// Starts a host-driven run of the agent `name` in the working folder
    /// `workingDirectory`.
    ///
    /// The run has no caller and depth one. An agent with no `model`, or
    /// with `model: inherit`, runs on ``AgentEnvironment/defaultSlot``. The
    /// run gets its own `agents` tool only when its `tools` key has an
    /// explicit `Agent`, `Agent(a, b)`, or `agents` entry. The run is
    /// in the index when the call returns.
    ///
    /// The working folder of the run is `workingDirectory`. With no folder,
    /// the run works in the folder of its creator, the host:
    /// ``AgentEnvironment/workingDirectory``. An agent never works in its own
    /// folder by default, also an agent of the agent folder form of a local
    /// layer (`<root>/<id>/AGENT.md`). Give ``AgentDefinition/folderURL``
    /// as `workingDirectory` for a run in the folder of the agent. The
    /// session of the run gets this folder, and the `AGENTS.md` documents of
    /// its instructions come from it. Each run that the run starts works in
    /// the same folder, unless its `start agent` call names a folder. A slash
    /// command of the runner gives the folder of the session that runs the
    /// command, thus a command run works in the folder of that session.
    ///
    /// - Parameters:
    ///   - name: The id of the agent in the catalog of the registry.
    ///   - prompt: The prompt of the run. It is `$ARGUMENTS` of the body and
    ///     the first user prompt of the session.
    ///   - workingDirectory: The working folder of the run, or `nil` for
    ///     ``AgentEnvironment/workingDirectory``.
    /// - Returns: The run. Its setup is done, thus it has its id.
    /// - Throws: ``AgentRunnerError/stopped`` after ``stop()``,
    ///   ``AgentRunnerError/catalogNotLoaded`` before the first
    ///   `AgentRegistry.load()`, or
    ///   ``AgentRunnerError/unknownAgent(name:available:)`` when the catalog
    ///   has no agent with the id `name`.
    public func start(
        _ name: String, prompt: String, workingDirectory: URL?
    ) async throws(AgentRunnerError) -> AgentRun {
        let definition: AgentDefinition
        do {
            definition = try startableDefinition(named: name)
        } catch {
            if error == .catalogNotLoaded {
                logStartBeforeLoad(of: name)
                countStartBeforeLoad(of: name)
            }
            throw error
        }
        return await start(
            AgentRunRequest(
                definition: definition, prompt: prompt, context: nil,
                inheritedSlot: environment.defaultSlot, depth: Self.hostDepth, parent: nil,
                agentsTool: AgentRun.agentsTool(of: self), requestedDirectory: workingDirectory))
    }

    /// Restores the run of a recorded child of a caller session, and
    /// continues it.
    ///
    /// The session is the recorded session of the child, not a new one. Its
    /// tools and instructions come from the current definition and catalog
    /// (``AgentSessionMaker/resolveSetup(for:family:)``). The run has the mail
    /// route to its caller: the caller session need not be live. The restore
    /// does not count against ``AgentEnvironment/maxConcurrentAgents``, and it
    /// checks ``AgentEnvironment/maxDepth``. The depth of the child is the
    /// depth of its caller run when the runner holds that run, else two.
    ///
    /// The run gets one first message, the text that tells it to read its
    /// transcript and go on. Choose the child with
    /// ``AgentRunRestore/select(children:statuses:)``.
    ///
    /// - Parameters:
    ///   - child: The recorded child.
    ///   - prompt: `$ARGUMENTS` of the body of the agent, or `nil` for the
    ///     recorded first prompt of the child (``RecordedChild/firstPrompt``),
    ///     and an empty text when the record holds none.
    ///   - deferStart: `true` to start the run at ``AgentRun/resume()``.
    ///   - claiming: The runs of this child, as a caller, that it claims in its
    ///     journal: the keys of its own interrupted children. A claimed run gets no
    ///     lost event, and the restored child of that run completes it.
    /// - Returns: The run, in operation.
    /// - Throws: ``AgentRunRestoreError``.
    public func restore(
        _ child: RecordedChild, prompt: String? = nil, deferStart: Bool = false, claiming: Set<RunKey> = [],
        caller: AgentRun? = nil
    ) async throws(AgentRunRestoreError) -> AgentRun {
        do {
            return try await restoreChild(
                child, prompt: prompt, deferStart: deferStart, claiming: claiming, caller: caller)
        } catch {
            // The child cannot work again, thus its original call in the journal of the live caller
            // ends as lost, and the caller does not wait for it.
            _ = await completeClaim(child.startCallKey, of: child.parentSessionId, outcome: .lost, detail: nil)
            throw error
        }
    }

    /// The work of ``restore(_:prompt:deferStart:claiming:)``.
    private func restoreChild(
        _ child: RecordedChild, prompt: String?, deferStart: Bool, claiming: Set<RunKey>, caller: AgentRun?
    ) async throws(AgentRunRestoreError) -> AgentRun {
        guard environment.sessionEnding != nil else { throw .sessionEndingMissing }
        if let caller, caller.id != child.parentSessionId { throw .callerMismatch }
        let definition: AgentDefinition
        do {
            definition = try startableDefinition(named: child.agentID)
        } catch {
            switch error {
            case .stopped: throw .stopped
            case .catalogNotLoaded: throw .catalogNotLoaded
            case .unknownAgent: throw .unknownAgent(child.agentID)
            }
        }
        retireEndedRuns()
        let callerRun = caller ?? openRuns[child.parentSessionId]
        let depth = (callerRun?.depth ?? Self.hostDepth) + 1
        guard depth <= environment.maxDepth else {
            throw .tooDeep(depth: depth, maxDepth: environment.maxDepth)
        }
        var request = AgentRunRequest(
            definition: definition, prompt: prompt ?? child.firstPrompt ?? "", context: nil,
            inheritedSlot: environment.defaultSlot, depth: depth, parent: nil,
            agentsTool: AgentRun.agentsTool(of: self))
        request.restoredCaller = child.parentSessionId
        request.restoredToken = child.parentToolCallId
        request.parent = callerRun?.parentRun
        let childID = child.sessionID
        let claimKey = child.startCallKey
        request.resultMail = { [weak self] final, report in
            guard let self else { return }
            let isClaimed = await self.completeClaim(
                claimKey, of: child.parentSessionId, outcome: Self.outcome(of: final), detail: report)
            // A completed claim is run mail in the transcript of the caller and starts no
            // answer. The short mail wakes the caller. Without a claim the mail holds the result.
            let text = isClaimed ? AgentsToolText.claimedResultWake : report
            _ = await self.mailCaller(text, from: childID, to: child.parentSessionId)
        }
        return try await withSetup(caller: child.parentSessionId) { () async throws(AgentRunRestoreError) -> AgentRun in
            let run = try await AgentRun.restore(
                request, sessionID: child.sessionID, claiming: claiming, environment: environment,
                renderer: renderer)
            openRuns[run.id] = run
            run.attach(changeHub)
            let startRequest = request.with(prompt: AgentsToolText.restoredRunContinue)
            let isAdopted = request.parent?.children.add(run) ?? true
            if deferStart {
                run.holdStart(startRequest, environment: environment)
            } else {
                run.begin(startRequest, environment: environment, adopt: false)
            }
            if !isAdopted {
                run.cancel()
            }
            return run
        }
    }

    /// Completes the original `start agent` call of a restored run in the journal of its
    /// caller. A caller that is a run of the runner completes it on its live session. Any other
    /// caller, for example the root session of the host, uses
    /// ``AgentEnvironment/claimCompletion``.
    ///
    /// - Parameters:
    ///   - key: The key of the claimed call.
    ///   - caller: The session of the caller.
    ///   - outcome: How the run ended.
    ///   - detail: The text of the result, or `nil`.
    /// - Returns: `true` when the caller held the claim and it is completed now.
    func completeClaim(
        _ key: RunKey, of caller: ULID, outcome: OperationOutcome, detail: String?
    ) async -> Bool {
        if let session = openRuns[caller]?.heldSession {
            return await session.completeClaimedRun(key, outcome: outcome, detail: detail)
        }
        return await environment.claimCompletion?(caller, key, outcome, detail) ?? false
    }

    /// The outcome of the original call for the final state of a restored run.
    private static func outcome(of final: AgentRunState) -> OperationOutcome {
        switch final {
        case .finished: .succeeded
        case .failed: .failed
        case .cancelled, .running: .cancelled
        }
    }

    /// Checks that the runner can start an agent, and gives its definition.
    ///
    /// - Parameter name: The id of the agent in the catalog of the registry.
    /// - Returns: The definition.
    /// - Throws: ``AgentRunnerError/stopped``,
    ///   ``AgentRunnerError/catalogNotLoaded``, or
    ///   ``AgentRunnerError/unknownAgent(name:available:)``.
    private func startableDefinition(named name: String) throws(AgentRunnerError) -> AgentDefinition {
        guard !isStopped else {
            throw .stopped
        }
        guard registry.isLoaded else {
            throw .catalogNotLoaded
        }
        let catalog = registry.catalog()
        guard let definition = catalog.definition(named: name) else {
            throw .unknownAgent(name: name, available: catalog.definitions.map(\.id))
        }
        return definition
    }

    /// Runs `body` while a setup of `caller` is in operation: a cancel call
    /// that the setup blocks waits until `body` ends, on each exit path.
    ///
    /// - Parameters:
    ///   - caller: The session of the caller, or `nil` for the host.
    ///   - body: The setup and the first steps of the run.
    /// - Returns: The value of `body`.
    /// - Throws: The error of `body`.
    private func withSetup<Value, Failure: Error>(
        caller: ULID?, _ body: () async throws(Failure) -> Value
    ) async throws(Failure) -> Value {
        let setupKey = ULID()
        setups[setupKey] = Setup(caller: caller)
        defer {
            for waiter in setups.removeValue(forKey: setupKey)?.waiters ?? [] {
                waiter.resume()
            }
        }
        return try await body()
    }

    /// Starts the run of `request`, and puts it in the index.
    ///
    /// While the setup is in operation, the start is in ``setups``. After
    /// the setup, the run goes in the index before its answers begin. Thus
    /// the run is in the index before its session can call a tool, and a
    /// read of the index from a step of the session finds the run. Then each
    /// cancel call that waits for the setup continues, and finds the run in
    /// the index.
    ///
    /// - Parameter request: The inputs of the run.
    /// - Returns: The run. Its setup is done, thus it has its id.
    func start(_ request: AgentRunRequest) async -> AgentRun {
        retireEndedRuns()
        return await withSetup(caller: request.context?.sessionID) { () async -> AgentRun in
            let run = await AgentRun.make(request, environment: environment, renderer: renderer)
            openRuns[run.id] = run
            run.attach(changeHub)
            run.begin(request, environment: environment)
            return run
        }
    }

    /// Starts the run of `request` when fewer than
    /// ``AgentEnvironment/maxConcurrentAgents`` runs are working.
    ///
    /// Only `start agent` calls it. A host-driven ``start(_:prompt:)`` and an
    /// answer to a final message do not check the limit. There is no queue:
    /// at the limit, the runner starts no run.
    ///
    /// The count holds each run in operation that does not wait for its
    /// children (``AgentRun/isWorking``), and not the calling run: after its
    /// answer the calling run waits for the new child, and a run that waits
    /// holds no place. Thus a fan-out of siblings does not block their
    /// children.
    ///
    /// - Parameter request: The inputs of the run.
    /// - Returns: ``LimitedStart/started(_:)`` with the run,
    ///   ``LimitedStart/atLimit(working:)`` with the count of working runs,
    ///   or ``LimitedStart/stopped`` after ``stop()``.
    func startWithinLimit(_ request: AgentRunRequest) async -> LimitedStart {
        guard !isStopped else {
            return .stopped
        }
        retireEndedRuns()
        let callerID = request.context?.sessionID
        // The limit does not count the calling run: the calling run is the
        // run whose session is the caller session. Do not compare with
        // `caller`, because that removes the children of the caller and
        // counts the calling run.
        let working = openRuns.values.count(where: { $0.isWorking && $0.sessionID != callerID })
            + limitedStartsInSetup
        guard working < environment.maxConcurrentAgents else {
            return .atLimit(working: working)
        }
        limitedStartsInSetup += 1
        defer { limitedStartsInSetup -= 1 }
        return .started(await start(request))
    }

    /// Finds a run by the completion token of its `start agent` call, in
    /// operation or in the records. A restored run has the token of its first
    /// life.
    ///
    /// - Parameter token: The token. The case of the letters does not matter.
    /// - Returns: The run, or `nil` when no run has the token.
    func run(completionToken token: String) -> AgentRun? {
        let wanted = token.uppercased()
        return (Array(openRuns.values) + records).first { $0.completionToken?.uppercased() == wanted }
    }

    /// Finds a run in operation or the record of a finished run.
    ///
    /// - Parameter id: The id of the run.
    /// - Returns: The run, or `nil` when the id is not known or the runner
    ///   removed its record.
    public func run(id: ULID) -> AgentRun? {
        retireEndedRuns()
        return openRuns[id] ?? records.first { $0.id == id }
    }

    /// Gives each run of one caller: the runs in operation and the records of
    /// the finished runs.
    ///
    /// - Parameter caller: The session of the caller, or `nil` for the
    ///   host-driven runs.
    /// - Returns: The runs whose ``AgentRun/caller`` is `caller`, sorted by
    ///   id.
    public func runs(caller: ULID?) -> [AgentRun] {
        retireEndedRuns()
        return (Array(openRuns.values) + records)
            .filter { $0.caller == caller }
            .sorted { $0.id < $1.id }
    }

    /// Sends `message` as mail to the session `caller`: the mail route of a
    /// caller link, for a caller that has no live `start agent` call of the
    /// sending run (a restored run).
    ///
    /// A caller that is a run in operation gets the message through
    /// ``AgentRun/deliver(_:from:)``, as a message from the session
    /// `sender`. Each other caller gets it through
    /// ``AgentEnvironment/callerMail``.
    ///
    /// - Parameters:
    ///   - message: The text of the message.
    ///   - sender: The id of the session that sends the message.
    ///   - caller: The id of the session that gets the message.
    /// - Returns: The id of the mail that was posted to the caller. `nil`
    ///   when the caller is a run that ended, or when the caller is not a run
    ///   of this runner and the environment has no ``AgentEnvironment/callerMail``.
    func mailCaller(_ message: String, from sender: ULID, to caller: ULID) async -> MailID? {
        retireEndedRuns()
        if let run = openRuns[caller] {
            return (try? run.deliver(message, from: .session(sender)))?.mailID
        }
        return await environment.callerMail?(message, sender, caller)
    }

    /// Gives the catalog of the registry with the warnings that need the
    /// environment.
    ///
    /// The catalog adds, for each agent in id order, the warning of a
    /// `model` value that matches no slot of the profile, then the warnings
    /// of the `tools` and `disallowedTools` entries that match no tool, then
    /// the warnings of the `skills` entries that name no skill or a skill
    /// that the `skills` tool hides. The diagnostics of the registry come
    /// first. This runner can make the `agents` tool for each run whose
    /// `tools` key lists it, thus an `Agent` entry matches a tool and gives
    /// no unknown-entry warning. When ``AgentEnvironment/maxDepth``
    /// is the depth of a host-started run, each run is at `maxDepth`. An
    /// `Agent` entry then gives a warning: a run with a caller gets only the
    /// message ops, and a host-started run gets no `agents` tool.
    ///
    /// - Returns: The catalog. It is empty before `registry.load()`.
    public nonisolated func catalog() -> AgentCatalog {
        let base = registry.catalog()
        let warnings = base.definitions.flatMap { definition in runWarnings(of: definition) }
        return AgentCatalog(definitions: base.definitions, diagnostics: base.diagnostics + warnings)
    }

    /// Stops the runner: it cancels each run, and waits for each to close its
    /// session.
    ///
    /// Each run in operation, and each start whose setup is in operation,
    /// goes to ``AgentRunState/cancelled``, unless its turn ended first. The
    /// call waits until the setup of each such start ends, then cancels the
    /// run. After this call, the runner starts no run:
    /// ``start(_:prompt:)`` throws ``AgentRunnerError/stopped``, and
    /// `start agent` gives a corrective.
    public func stop() async {
        isStopped = true
        await cancelRuns(forShutdown: true, where: { _ in true })
        changeHub.finish()
    }

    /// Cancels each run of one caller, and waits for each to close its
    /// session.
    ///
    /// `RoutedSession.close()` does not know the runs that the session
    /// started. Thus the host calls this before it closes a session that has
    /// the `agents` tool. The call cancels each run in operation of the
    /// caller. It also waits until the setup of each start of the caller
    /// that is in setup ends, then cancels that run. Each such run goes to
    /// ``AgentRunState/cancelled``, unless its answers ended first. All of
    /// this occurs before the call returns, thus no run of the caller is in
    /// operation when the host closes the session. The runs of each other
    /// caller stay as they are.
    ///
    /// - Parameter caller: The id of the session of the caller.
    public func cancelRuns(caller: ULID) async {
        await cancelRuns(forShutdown: false, where: { $0 == caller })
    }

    /// Cancels each run whose caller `isTarget` selects, and waits for each
    /// to end. Then moves each ended run to the records.
    ///
    /// The call cancels the runs in operation first, thus they do not work
    /// while the call waits for the setups. It then waits for the end of
    /// each setup of a selected start. At last, it cancels each selected run
    /// of the index and waits for its final state. That last step also
    /// holds each run whose setup ended during the wait.
    ///
    /// - Parameter isTarget: Selects a caller: a session id, or `nil` for
    ///   the host.
    private func cancelRuns(forShutdown: Bool, where isTarget: (ULID?) -> Bool) async {
        let setupKeys = setups.filter { isTarget($0.value.caller) }.map(\.key)
        for run in openRuns.values where isTarget(run.caller) {
            forShutdown ? run.cancelForShutdown() : run.cancel()
        }
        for setupKey in setupKeys {
            await endOfSetup(setupKey)
        }
        let runs = openRuns.values.filter { isTarget($0.caller) }
        for run in runs {
            forShutdown ? run.cancelForShutdown() : run.cancel()
        }
        for run in runs {
            _ = await run.finalState()
        }
        retireEndedRuns()
    }

    /// Waits until the setup of the start `setupKey` ends.
    ///
    /// - Parameter setupKey: The key of the start in ``setups``. The call
    ///   returns at once when the setup ended already.
    private func endOfSetup(_ setupKey: ULID) async {
        await withCheckedContinuation { continuation in
            guard setups[setupKey] != nil else {
                continuation.resume()
                return
            }
            setups[setupKey]?.waiters.append(continuation)
        }
    }

    /// Gives the warnings of one agent that need the environment.
    ///
    /// - Parameter definition: The agent.
    /// - Returns: The `model` warning, then the tool warnings, then the skill
    ///   warnings.
    private nonisolated func runWarnings(of definition: AgentDefinition) -> [AgentDiagnostic] {
        let model = ModelMatch.match(
            definition.model, profile: environment.profile, inherited: environment.defaultSlot)
        let modelWarnings = model.warning.map { message in
            [AgentFinding(code: .unmatchedModel, severity: .warning, message: message)
                .diagnostic(agent: definition.id, provenance: definition.provenance)]
        } ?? []
        return modelWarnings
            + ToolResolver.diagnostics(
                of: definition, catalog: environment.tools, hasAgentsTool: true,
                atMaxDepth: environment.maxDepth <= Self.hostDepth)
            + environment.skillsPreload.diagnostics(of: definition)
    }

    /// Moves each ended run from the runs in operation to the records, in
    /// id order, then removes the oldest records above
    /// ``AgentEnvironment/maxRetainedRuns``.
    func retireEndedRuns() {
        let ended = openRuns.values.filter { $0.state != .running }.sorted { $0.id < $1.id }
        for run in ended {
            openRuns[run.id] = nil
        }
        records += ended
        let excess = records.count - environment.maxRetainedRuns
        guard excess > 0 else { return }
        records.removeFirst(excess)
    }
}
