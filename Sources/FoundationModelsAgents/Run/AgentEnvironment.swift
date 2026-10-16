import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import FoundationModelsSkills
import Logging
import Metrics
import Tracing

/// The dependencies and the limits of the agent runs of one host.
///
/// The host makes the dependencies. The profile and the skills registry
/// have no default: the host session and the sub-agents use the same
/// instances.
///
/// The skills registry is the one source of the skills. The environment
/// makes the `skills` tool from it, and puts that tool in its tool catalog
/// under the name `skills`. The `skills:` preload of each run reads the same
/// registry, with the same visibility rule. The host gives its root session
/// ``skillsTool``, thus the host and the runs see the same skills.
///
/// ```swift
/// let env = try await AgentEnvironment.make(profile: profile, skills: skills,
///                                           workingDirectory: projectURL, tools: tools,
///                                           defaultSlot: .standard, maxConcurrentAgents: 4, maxDepth: 3)
/// let root = profile.standard.makeSession(
///     configuration: SessionConfiguration(
///         instructions: instructions, tools: [env.skillsTool, agentsTool], userPresence: .headless))
/// ```
public struct AgentEnvironment: Sendable {
    /// Tells if the `skills` tool shows a skill. The `skills:` preload uses
    /// the same rule.
    public typealias SkillsVisibility = @Sendable (SkillMetadata) -> Bool

    /// Makes the token budget of a run from the resolved context of its
    /// model, in tokens. `nil` gives a run with no budget.
    public typealias BudgetFactory = @Sendable (Int) -> TokenBudget?

    /// Receives each session output of one agent run, with that run. The
    /// output holds the event and its origin, thus a host can follow the id
    /// chain from the mail to the event. ``runEventObserver`` tells the
    /// contract.
    public typealias RunEventObserver = @Sendable (AgentRun, SessionOutput) -> Void

    /// The default of ``maxConcurrentAgents``.
    public static let defaultMaxConcurrentAgents = 4

    /// The default of ``maxDepth``.
    public static let defaultMaxDepth = 3

    /// The default of ``maxRetainedRuns``.
    public static let defaultMaxRetainedRuns = 100

    /// The default of ``budget``: `TokenBudget(limit:)` with the resolved
    /// context of the model.
    public static let defaultBudget: BudgetFactory = { TokenBudget(limit: $0) }

    /// The default visibility rule of the `skills` tool: it shows each skill
    /// that the model can see (`SkillMetadata.isModelVisible`).
    public static let defaultSkillsVisibility: SkillsVisibility = { $0.isModelVisible }

    /// The resolved profile. Each run makes its session on
    /// `profile.standard` or `profile.flash`.
    public let profile: LanguageModelProfile

    /// The skills registry of the host. The `skills` tool and the `skills:`
    /// key of an agent read it.
    public let skills: SkillsRegistry

    /// The `skills` tool, made from ``skills``.
    ///
    /// ``tools`` holds this tool under its name, `skills`, thus each run gets
    /// it. Give it to the root session of the host too: then the host and the
    /// runs read one registry.
    public let skillsTool: SkillsCatalogTool

    /// The visibility rule of ``skillsTool``. The `skills:` preload skips each
    /// skill that this rule hides.
    let skillsVisibility: SkillsVisibility

    /// The model that chooses among the candidates of a `search skill` call
    /// of ``skillsTool`` and of a `find agents` call of the `agents` tool, or
    /// `nil` for the retrieval rank with no model.
    let selectionModel: (any FoundationModels.LanguageModel)?

    /// The working directory of each run that has no other folder: no folder
    /// of the start request, no parent run, and no agent folder of the
    /// agent-folder source (``AgentRunner/start(_:prompt:workingDirectory:)``).
    public let workingDirectory: URL

    /// The tools that the `tools` and `disallowedTools` keys select from: the
    /// tools of the host, and ``skillsTool`` under the name `skills`.
    public let tools: ToolCatalog

    /// The slot of a host-started run when its `model` is absent or
    /// `inherit`. It is `.standard` or `.flash`.
    public let defaultSlot: ModelSlot

    /// The count of runs that can have a turn in operation at one time. It
    /// is one or more.
    public let maxConcurrentAgents: Int

    /// The depth limit. A host-started run has depth one, and a child has
    /// the depth of its parent plus one. It is one or more.
    public let maxDepth: Int

    /// The count of finished run records that the runner keeps for
    /// `check agent`. The runner removes the oldest record first. It is
    /// zero or more.
    public let maxRetainedRuns: Int

    /// Makes the token budget of each run from the resolved context of its
    /// model.
    public let budget: BudgetFactory

    /// The tracer of the span of each run, or `nil` to read
    /// `InstrumentationSystem.tracer` when the run starts.
    ///
    /// `nil` is the default. A host that bootstraps a tracing backend after
    /// it makes the environment still gets the spans, because the run reads
    /// the tracer only when it starts. A child run starts in the body of a
    /// `start agent` call, under the detached pump of the Router, thus a
    /// task-local tracer of `withTracer` does not reach it. Give the tracer
    /// here, and to `Router(tracer:)`, to send each span to one tracer that
    /// is not the bootstrapped one.
    public let tracer: (any Tracer)?

    /// The logger of the log records of each run, or `nil` to make a new
    /// `Logger` with the label of the package when each run starts.
    ///
    /// `nil` is the default. The package never bootstraps the logging
    /// system: a new logger uses the backend that the host bootstrapped. A
    /// child run starts in the body of a `start agent` call, under the
    /// detached pump of the Router, thus a log handler that the host binds
    /// to its own task does not reach it. Give a logger here to send the
    /// records of each run, the child runs too, to one handler.
    public let logger: Logger?

    /// The metrics factory of the run counter and the run timer, or `nil` to
    /// read `MetricsSystem.factory` when each run ends.
    ///
    /// `nil` is the default. The package never bootstraps the metrics
    /// system: with `nil`, each run uses the factory that the host
    /// bootstrapped, or the task-local factory of `withMetricsFactory`. A
    /// child run starts in the body of a `start agent` call, under the
    /// detached pump of the Router, thus a task-local factory does not reach
    /// it. Give a factory here to send the metrics of each run, the child
    /// runs too, to one factory.
    public let metricsFactory: (any MetricsFactory)?

    /// The settle period of the session of each run, in seconds: how long a
    /// background call of the run, for example `start agent`, waits for its
    /// own work. Never negative.
    ///
    /// Work that ends in this time gives its own output to the call. Work
    /// that continues gives the pending envelope, and its result comes later
    /// as mail. `0` gives the pending envelope at once. The session of each
    /// run gets this value as `SessionConfiguration.inlineSettleGrace`.
    public let inlineSettleGrace: TimeInterval

    /// The observer of the session events of each run, or `nil` for no
    /// observer. `nil` is the default.
    ///
    /// The observer gets each ``SessionOutput``: the event and its origin.
    /// Each run calls the observer, the child runs too. The run reads the
    /// session-event subscription of its session in one loop, and calls the
    /// observer synchronously in that loop, first for each event, before the
    /// run uses the event. Thus the observer gets the events of one run in
    /// the order of that subscription. The observer holds the loop of the
    /// run while it runs: it must return quickly, and it must not wait for
    /// the run. Two runs can call it at the same time.
    ///
    /// The open ``SessionEvent/toolInvocation(_:toolCallID:)`` record of a
    /// tool run carries the completion token of that tool run. The Router
    /// gives the open record to the subscription before the body of the
    /// tool starts. The loop of the run and the body of the tool are two
    /// tasks, thus the observer gets the open record while the body runs
    /// at the latest, and normally before the body gives output. The
    /// package does not promise that the observer runs before the first
    /// output of the body.
    public let runEventObserver: RunEventObserver?

    /// The most answers in a row that mail alone starts in the session of a
    /// run, with no caller message between them. Message mail and final
    /// messages both count. When the Router holds the mail at this limit,
    /// the run pauses: it waits until each run that it started ended, then it
    /// fails with ``AgentRunFailure/mailDeliveryPaused(_:)`` and the held
    /// results (``AgentRun/pause``). The limit is a guard against a chain of
    /// mail with no end, thus the run does not end the hold itself.
    ///
    /// The default is the default of the Router,
    /// `SessionConfiguration.defaultMailOnlyAnswerLimit`.
    var mailOnlyAnswerLimit = SessionConfiguration.defaultMailOnlyAnswerLimit

    /// The user presence of the session of each run that has no question
    /// target, for example a host-started run. It is `.headless`: nothing can
    /// answer a question of that run session, thus a question of the run
    /// ends at once with a cancel that gives `RunPlane.noUserPresentReason`,
    /// and the run goes on. A run that a `start agent` call started takes the
    /// user presence of the session of that call, and sends its questions to
    /// that session (``AgentRunRequest/questionTarget``).
    ///
    /// Only tests change this value: an interactive run session lets a test
    /// reach the question guard of the run (``AgentRun/answerQuestion(of:on:)``).
    var runUserPresence = UserPresence.headless

    /// Makes an environment, and makes its `skills` tool from `skills`.
    ///
    /// The function is `async throws` because `SkillsTool.make` reads the
    /// registry and builds the search index of the tool.
    ///
    /// A value out of its range is a programmer error and stops the process.
    /// A `skills` entry in `tools` is a programmer error too: the environment
    /// adds the `skills` tool itself, thus the runs and the preload cannot
    /// read two registries.
    ///
    /// - Parameters:
    ///   - profile: The resolved profile of the host.
    ///   - skills: The skills registry of the host. The `skills` tool and the
    ///     `skills:` preload read this one registry.
    ///   - skillsSelectionModel: The model that chooses among the candidate
    ///     skills of a `search skill` call (`SkillsTool.make(registry:model:)`),
    ///     or `nil` (the default) for a keyword search with no model
    ///     (`SkillsTool.make(registry:)`). The `find agents` operation of the
    ///     `agents` tool uses the same model to choose among the candidate
    ///     agents.
    ///   - skillsCatalogCharacterLimit: The most characters that the catalog
    ///     list in the description of the `skills` tool can have. The default
    ///     is `SkillsTool.defaultCatalogCharacterLimit`.
    ///   - skillsVisibility: Tells if the `skills` tool shows a skill. The
    ///     `skills:` preload skips each skill that it hides. The default is
    ///     ``defaultSkillsVisibility``.
    ///   - workingDirectory: The working directory of each run that has no
    ///     other folder (``workingDirectory``). The default is the current
    ///     directory of the process.
    ///   - tools: The tool catalog of the host. It must not hold a `skills`
    ///     entry. The default is an empty catalog.
    ///   - defaultSlot: The slot of a host-started run with no `model`. It
    ///     must be `.standard` or `.flash`.
    ///   - maxConcurrentAgents: The count of runs that can have a turn in
    ///     operation at one time. It must be one or more.
    ///   - maxDepth: The depth limit. It must be one or more.
    ///   - maxRetainedRuns: The count of finished run records to keep. It
    ///     must be zero or more.
    ///   - budget: Makes the token budget of each run.
    ///   - tracer: The tracer of the span of each run, or `nil` (the
    ///     default) to read `InstrumentationSystem.tracer` when the run
    ///     starts.
    ///   - logger: The logger of the log records of each run, or `nil` (the
    ///     default) to make a new `Logger` when each run starts.
    ///   - metricsFactory: The metrics factory of the metrics of each run, or
    ///     `nil` (the default) to read `MetricsSystem.factory` when each run
    ///     ends.
    ///   - inlineSettleGrace: The settle period of the session of each run,
    ///     in seconds. The default is `ToolMount.defaultInlineSettleGrace`. A
    ///     negative value acts as `0`.
    ///   - runEventObserver: The observer of the session events of each run,
    ///     or `nil` (the default) for no observer. ``runEventObserver`` tells
    ///     the contract.
    /// - Returns: The environment.
    /// - Throws: Whatever `SkillsTool.make` throws.
    public static func make(
        profile: LanguageModelProfile,
        skills: SkillsRegistry,
        skillsSelectionModel: (any FoundationModels.LanguageModel)? = nil,
        skillsCatalogCharacterLimit: Int = SkillsTool.defaultCatalogCharacterLimit,
        skillsVisibility: @escaping SkillsVisibility = defaultSkillsVisibility,
        workingDirectory: URL = URL.currentDirectory(),
        tools: ToolCatalog = ToolCatalog(),
        defaultSlot: ModelSlot = .standard,
        maxConcurrentAgents: Int = defaultMaxConcurrentAgents,
        maxDepth: Int = defaultMaxDepth,
        maxRetainedRuns: Int = defaultMaxRetainedRuns,
        budget: @escaping BudgetFactory = defaultBudget,
        tracer: (any Tracer)? = nil,
        logger: Logger? = nil,
        metricsFactory: (any MetricsFactory)? = nil,
        inlineSettleGrace: TimeInterval = ToolMount.defaultInlineSettleGrace,
        runEventObserver: RunEventObserver? = nil
    ) async throws -> AgentEnvironment {
        let skillsTool = try await makeSkillsTool(
            skills: skills, selectionModel: skillsSelectionModel,
            catalogCharacterLimit: skillsCatalogCharacterLimit, visibility: skillsVisibility)
        return AgentEnvironment(
            profile: profile, skills: skills, skillsTool: skillsTool, skillsVisibility: skillsVisibility,
            selectionModel: skillsSelectionModel, workingDirectory: workingDirectory, tools: tools,
            defaultSlot: defaultSlot, maxConcurrentAgents: maxConcurrentAgents, maxDepth: maxDepth,
            maxRetainedRuns: maxRetainedRuns, budget: budget, tracer: tracer, logger: logger,
            metricsFactory: metricsFactory, inlineSettleGrace: inlineSettleGrace, runEventObserver: runEventObserver)
    }

    /// Makes the `skills` tool from `skills`.
    ///
    /// - Parameters:
    ///   - skills: The skills registry of the host.
    ///   - selectionModel: The model of the selection tier, or `nil` for a
    ///     keyword search with no model.
    ///   - catalogCharacterLimit: The most characters of the catalog list of
    ///     the description.
    ///   - visibility: Tells if the tool shows a skill.
    /// - Returns: The tool.
    /// - Throws: Whatever `SkillsTool.make` throws.
    static func makeSkillsTool(
        skills: SkillsRegistry,
        selectionModel: (any FoundationModels.LanguageModel)?,
        catalogCharacterLimit: Int,
        visibility: @escaping SkillsVisibility
    ) async throws -> SkillsCatalogTool {
        guard let selectionModel else {
            return try await SkillsTool.make(
                registry: skills, catalogCharacterLimit: catalogCharacterLimit, visibilityPredicate: visibility)
        }
        return try await SkillsTool.make(
            registry: skills, model: selectionModel, catalogCharacterLimit: catalogCharacterLimit,
            visibilityPredicate: visibility)
    }

    /// Makes an environment over a `skills` tool that is already made.
    ///
    /// ``make(profile:skills:skillsSelectionModel:skillsCatalogCharacterLimit:skillsVisibility:workingDirectory:tools:defaultSlot:maxConcurrentAgents:maxDepth:maxRetainedRuns:budget:tracer:logger:metricsFactory:inlineSettleGrace:runEventObserver:)``
    /// tells each parameter. `skillsTool` must be the tool that
    /// ``makeSkillsTool(skills:selectionModel:catalogCharacterLimit:visibility:)``
    /// made from `skills` and `skillsVisibility`. The init adds it to `tools`
    /// under its name. `selectionModel` is the model of the selection tier of
    /// `find agents`, and the default is `nil`. Give the model that made
    /// `skillsTool`, thus both tools choose with one model.
    ///
    /// A value out of its range, and a `skills` entry in `tools`, are
    /// programmer errors and stop the process.
    init(
        profile: LanguageModelProfile,
        skills: SkillsRegistry,
        skillsTool: SkillsCatalogTool,
        skillsVisibility: @escaping SkillsVisibility,
        selectionModel: (any FoundationModels.LanguageModel)? = nil,
        workingDirectory: URL,
        tools: ToolCatalog,
        defaultSlot: ModelSlot,
        maxConcurrentAgents: Int,
        maxDepth: Int,
        maxRetainedRuns: Int,
        budget: @escaping BudgetFactory,
        tracer: (any Tracer)?,
        logger: Logger?,
        metricsFactory: (any MetricsFactory)?,
        inlineSettleGrace: TimeInterval,
        runEventObserver: RunEventObserver? = nil
    ) {
        precondition(
            ModelMatch.generationSlots.contains { $0.slot == defaultSlot },
            "defaultSlot must be .standard or .flash")
        precondition(maxConcurrentAgents >= 1, "maxConcurrentAgents must be one or more")
        precondition(maxDepth >= 1, "maxDepth must be one or more")
        precondition(maxRetainedRuns >= 0, "maxRetainedRuns must be zero or more")
        precondition(
            !tools.names.contains(skillsTool.name),
            "tools must not hold a '\(skillsTool.name)' entry: the environment adds the skills tool")
        var catalog = tools
        catalog.register(skillsTool.name) { skillsTool }
        self.profile = profile
        self.skills = skills
        self.skillsTool = skillsTool
        self.skillsVisibility = skillsVisibility
        self.selectionModel = selectionModel
        self.workingDirectory = workingDirectory
        self.tools = catalog
        self.defaultSlot = defaultSlot
        self.maxConcurrentAgents = maxConcurrentAgents
        self.maxDepth = maxDepth
        self.maxRetainedRuns = maxRetainedRuns
        self.budget = budget
        self.tracer = tracer
        self.logger = logger
        self.metricsFactory = metricsFactory
        self.inlineSettleGrace = max(0, inlineSettleGrace)
        self.runEventObserver = runEventObserver
    }
}
