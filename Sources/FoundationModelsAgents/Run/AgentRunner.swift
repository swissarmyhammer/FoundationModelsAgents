import FoundationModelsRouter
import ULID

/// The actor that owns each agent run of one host (plan.md §8.1, §9.3).
///
/// The runner starts runs, keeps the index of the runs, and keeps the records
/// of the finished runs. It is not a session system, a tool loop, a recorder,
/// or a display model. One runner holds one profile: the profile of its
/// environment.
///
/// The init stores its inputs and does no I/O. The runner reads
/// `registry.catalog()` at each call, thus the host calls
/// `AgentRegistry.load()` before the first ``start(_:prompt:)``. Before the
/// load, the catalog is empty and each ``start(_:prompt:)`` throws
/// ``AgentRunnerError/unknownAgent(name:available:)``. After a
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
    /// One run of the index, and the completion token of the tool call that
    /// started it.
    private struct Entry {
        /// The run. It holds its caller, its slot, and its depth.
        let run: AgentRun

        /// The `ToolContext.completionToken` of the tool call that started
        /// the run, or `nil` for a host-driven run.
        let completionToken: String?
    }

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

    /// The depth of a host-started run (plan.md §9.3).
    static let hostDepth = 1

    /// The registry that gives the definitions.
    let registry: AgentRegistry

    /// The dependencies and the limits of the runs.
    let environment: AgentEnvironment

    /// Renders the body of each agent.
    private let renderer: AgentBodyRenderer

    /// The runs whose turn can be in operation, by id.
    private var openRuns: [ULID: Entry] = [:]

    /// The finished runs, oldest first. Each run holds its id, its agent,
    /// and its final state with the final text.
    private var records: [Entry] = []

    /// The id of each run in the index, by the completion token of the tool
    /// call that started it.
    private var runIDsByCompletionToken: [String: ULID] = [:]

    /// The count of limited starts whose setup is in operation. The actor
    /// can run a second call while a setup waits, thus the limit counts
    /// these starts too.
    private var limitedStartsInSetup = 0

    /// The starts whose setup is in operation, by a key of each start.
    /// ``cancelRuns(caller:)`` and ``stop()`` wait for these setups.
    private var setups: [ULID: Setup] = [:]

    /// `true` after ``stop()``. The runner then starts no run.
    private var isStopped = false

    /// Makes a runner. It stores its inputs and does no I/O.
    ///
    /// - Parameters:
    ///   - registry: The registry that gives the definitions. The host calls
    ///     its `load()` before the first run.
    ///   - environment: The dependencies and the limits of the runs.
    public init(registry: AgentRegistry, environment: AgentEnvironment) {
        self.registry = registry
        self.environment = environment
        self.renderer = AgentBodyRenderer(registry: registry)
    }

    /// The runs whose turn is in operation, sorted by id.
    public var runs: [AgentRun] {
        retireEndedRuns()
        return openRuns.values.lazy.map(\.run).sorted { $0.id < $1.id }
    }

    /// Starts a host-driven run of the agent `name` (plan.md §9.3).
    ///
    /// The run has no caller and depth one. An agent with no `model`, or
    /// with `model: inherit`, runs on ``AgentEnvironment/defaultSlot``. The
    /// run gets its own `agents` tool when its `tools` permit it. The run is
    /// in the index when the call returns.
    ///
    /// - Parameters:
    ///   - name: The id of the agent in the catalog of the registry.
    ///   - prompt: The prompt of the run. It is `$ARGUMENTS` of the body and
    ///     the first user prompt of the session.
    /// - Returns: The run. Its setup is done, thus it has its id.
    /// - Throws: ``AgentRunnerError/stopped`` after ``stop()``, or
    ///   ``AgentRunnerError/unknownAgent(name:available:)`` when the catalog
    ///   has no agent with the id `name`.
    public func start(_ name: String, prompt: String) async throws(AgentRunnerError) -> AgentRun {
        guard !isStopped else {
            throw .stopped
        }
        let catalog = registry.catalog()
        guard let definition = catalog.definition(named: name) else {
            throw .unknownAgent(name: name, available: catalog.definitions.map(\.id))
        }
        return await start(
            AgentRunRequest(
                definition: definition, prompt: prompt, context: nil,
                inheritedSlot: environment.defaultSlot, depth: Self.hostDepth, parent: nil,
                agentsTool: AgentRun.agentsTool(of: self)))
    }

    /// Starts the run of `request`, and puts it in the index.
    ///
    /// While the setup is in operation, the start is in ``setups``. After
    /// the setup, the run goes in the index, and then each cancel call that
    /// waits for the setup continues. Thus that call finds the run in the
    /// index.
    ///
    /// - Parameter request: The inputs of the run.
    /// - Returns: The run. Its setup is done, thus it has its id.
    func start(_ request: AgentRunRequest) async -> AgentRun {
        retireEndedRuns()
        let setupKey = ULID()
        setups[setupKey] = Setup(caller: request.context?.sessionID)
        let run = await AgentRun.start(request, environment: environment, renderer: renderer)
        let entry = Entry(run: run, completionToken: request.context?.completionToken)
        openRuns[run.id] = entry
        if let token = entry.completionToken {
            runIDsByCompletionToken[token] = run.id
        }
        for waiter in setups.removeValue(forKey: setupKey)?.waiters ?? [] {
            waiter.resume()
        }
        return run
    }

    /// Starts the run of `request` when fewer than
    /// ``AgentEnvironment/maxConcurrentAgents`` runs are working
    /// (plan.md §9.3, the limit).
    ///
    /// Only `start agent` calls it. A host-driven ``start(_:prompt:)``, a
    /// child-delivery turn, and a final-answer turn do not check the limit.
    /// There is no queue: at the limit, the runner starts no run.
    ///
    /// The count holds each run in operation that does not wait for its
    /// children (``AgentRun/isWorking``), and not the calling run: after its
    /// turn the calling run waits for the new child, and a run that waits
    /// holds no place (plan.md §9.3). Thus a fan-out of siblings does not
    /// block their children.
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
        let working = openRuns.values.count(where: { $0.run.isWorking && $0.run.id != callerID })
            + limitedStartsInSetup
        guard working < environment.maxConcurrentAgents else {
            return .atLimit(working: working)
        }
        limitedStartsInSetup += 1
        defer { limitedStartsInSetup -= 1 }
        return .started(await start(request))
    }

    /// Finds a run in operation or the record of a finished run.
    ///
    /// - Parameter id: The id of the run.
    /// - Returns: The run, or `nil` when the id is not known or the runner
    ///   removed its record.
    public func run(id: ULID) -> AgentRun? {
        retireEndedRuns()
        return openRuns[id]?.run ?? records.first { $0.run.id == id }?.run
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
        return (Array(openRuns.values) + records).lazy.map(\.run)
            .filter { $0.caller == caller }
            .sorted { $0.id < $1.id }
    }

    /// Finds the run that a tool call started.
    ///
    /// - Parameter completionToken: The `ToolContext.completionToken` of the
    ///   tool call.
    /// - Returns: The run, or `nil` when no run of the index has the token.
    func run(completionToken: String) -> AgentRun? {
        runIDsByCompletionToken[completionToken].flatMap { id in run(id: id) }
    }

    /// Gives the catalog of the registry with the warnings that need the
    /// environment (plan.md §7, §10).
    ///
    /// The catalog adds, for each agent in id order, the warning of a
    /// `model` value that matches no slot of the profile, then the warnings
    /// of the `tools` and `disallowedTools` entries that match no tool, then
    /// the warnings of the `skills` entries that name no skill or a skill
    /// that is not model-visible (plan.md §5). The diagnostics of the
    /// registry come first. Each run of this runner gets the `agents` tool,
    /// thus `Agent` entries match it.
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
        await cancelRuns { _ in true }
    }

    /// Cancels each run of one caller, and waits for each to close its
    /// session (plan.md §9.2, a closed caller).
    ///
    /// `RoutedSession.close()` does not know the runs that the session
    /// started. Thus the host calls this before it closes a session that has
    /// the `agents` tool. The call cancels each run in operation of the
    /// caller. It also waits until the setup of each start of the caller
    /// that is in setup ends, then cancels that run. Each such run posts its
    /// final message, then goes to ``AgentRunState/cancelled``, unless its
    /// turn ended first. All of this occurs before the call returns, thus no
    /// run posts into the session after the host closes it. The runs of each
    /// other caller stay as they are.
    ///
    /// - Parameter caller: The id of the session of the caller.
    public func cancelRuns(caller: ULID) async {
        await cancelRuns { $0 == caller }
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
    private func cancelRuns(where isTarget: (ULID?) -> Bool) async {
        let setupKeys = setups.filter { isTarget($0.value.caller) }.map(\.key)
        for run in openRuns.values.lazy.map(\.run) where isTarget(run.caller) {
            run.cancel()
        }
        for setupKey in setupKeys {
            await endOfSetup(setupKey)
        }
        let runs = openRuns.values.filter { isTarget($0.run.caller) }.map(\.run)
        for run in runs {
            run.cancel()
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
            [AgentFinding(severity: .warning, message: message)
                .diagnostic(agent: definition.id, provenance: definition.provenance)]
        } ?? []
        return modelWarnings
            + ToolResolver.diagnostics(of: definition, catalog: environment.tools, hasAgentsTool: true)
            + AgentSkillsPreload(skills: environment.skills).diagnostics(of: definition)
    }

    /// Moves each ended run from the runs in operation to the records, in
    /// id order, then removes the oldest records above
    /// ``AgentEnvironment/maxRetainedRuns``.
    private func retireEndedRuns() {
        let ended = openRuns.values.filter { $0.run.state != .running }.sorted { $0.run.id < $1.run.id }
        for entry in ended {
            openRuns[entry.run.id] = nil
        }
        records += ended
        let excess = records.count - environment.maxRetainedRuns
        guard excess > 0 else { return }
        for token in records.prefix(excess).compactMap(\.completionToken) {
            runIDsByCompletionToken[token] = nil
        }
        records.removeFirst(excess)
    }
}
