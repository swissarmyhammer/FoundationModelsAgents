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

    /// The outcome of a start that checks
    /// ``AgentEnvironment/maxConcurrentAgents``.
    enum LimitedStart {
        /// The runner started the run and put it in the index.
        case started(AgentRun)

        /// The limit is full: `working` runs have a turn in operation, and
        /// the runner started no run.
        case atLimit(working: Int)
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
    /// - Throws: ``AgentRunnerError/unknownAgent(name:available:)`` when the
    ///   catalog has no agent with the id `name`.
    public func start(_ name: String, prompt: String) async throws(AgentRunnerError) -> AgentRun {
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
    /// - Parameter request: The inputs of the run.
    /// - Returns: The run. Its setup is done, thus it has its id.
    func start(_ request: AgentRunRequest) async -> AgentRun {
        retireEndedRuns()
        let run = await AgentRun.start(request, environment: environment, renderer: renderer)
        let entry = Entry(run: run, completionToken: request.context?.completionToken)
        openRuns[run.id] = entry
        if let token = entry.completionToken {
            runIDsByCompletionToken[token] = run.id
        }
        return run
    }

    /// Starts the run of `request` when fewer than
    /// ``AgentEnvironment/maxConcurrentAgents`` runs are working
    /// (plan.md §9.3, the limit).
    ///
    /// Only `start agent` calls it. A host-driven ``start(_:prompt:)`` and a
    /// child-delivery turn do not check the limit. There is no queue: at the
    /// limit, the runner starts no run.
    ///
    /// The count holds each run in operation that does not wait for its
    /// children (``AgentRun/isWorking``), and not the calling run: after its
    /// turn the calling run waits for the new child, and a run that waits
    /// holds no place (plan.md §9.3). Thus a fan-out of siblings does not
    /// block their children.
    ///
    /// - Parameter request: The inputs of the run.
    /// - Returns: ``LimitedStart/started(_:)`` with the run, or
    ///   ``LimitedStart/atLimit(working:)`` with the count of working runs.
    func startWithinLimit(_ request: AgentRunRequest) async -> LimitedStart {
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

    /// Cancels each run in operation, and waits for each to close its
    /// session. Each such run goes to ``AgentRunState/cancelled``, unless its
    /// turn ended first.
    public func stop() async {
        await cancel(openRuns.values.map(\.run))
    }

    /// Cancels each run in operation of one caller, and waits for each to
    /// close its session (plan.md §9.2, a closed caller).
    ///
    /// `RoutedSession.close()` does not know the runs that the session
    /// started. Thus the host calls this before it closes a session that has
    /// the `agents` tool. Each such run posts its final message, then goes
    /// to ``AgentRunState/cancelled``, unless its turn ended first. The runs
    /// of each other caller stay as they are.
    ///
    /// - Parameter caller: The id of the session of the caller.
    public func cancelRuns(caller: ULID) async {
        await cancel(Array(openRuns.values.lazy.map(\.run).filter { $0.caller == caller }))
    }

    /// Cancels each run of `runs`, waits for each to end, and then moves
    /// each ended run to the records.
    ///
    /// - Parameter runs: The runs to cancel.
    private func cancel(_ runs: [AgentRun]) async {
        for run in runs {
            run.cancel()
        }
        for run in runs {
            _ = await run.finalState()
        }
        retireEndedRuns()
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
