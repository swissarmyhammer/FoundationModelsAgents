import Foundation
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
/// ```swift
/// let env = AgentEnvironment(profile: profile, skills: skills,
///                            workingDirectory: projectURL, tools: tools,
///                            defaultSlot: .standard, maxConcurrentAgents: 4, maxDepth: 3)
/// ```
public struct AgentEnvironment: Sendable {
    /// Makes the token budget of a run from the resolved context of its
    /// model, in tokens. `nil` gives a run with no budget.
    public typealias BudgetFactory = @Sendable (Int) -> TokenBudget?

    /// The default of ``maxConcurrentAgents``.
    public static let defaultMaxConcurrentAgents = 4

    /// The default of ``maxDepth``.
    public static let defaultMaxDepth = 3

    /// The default of ``maxRetainedRuns``.
    public static let defaultMaxRetainedRuns = 100

    /// The default of ``budget``: `TokenBudget(limit:)` with the resolved
    /// context of the model.
    public static let defaultBudget: BudgetFactory = { TokenBudget(limit: $0) }

    /// The resolved profile. Each run makes its session on
    /// `profile.standard` or `profile.flash`.
    public let profile: LanguageModelProfile

    /// The skills registry that the `skills:` key of an agent reads.
    public let skills: SkillsRegistry

    /// The working directory of each run.
    public let workingDirectory: URL

    /// The tools that the `tools` and `disallowedTools` keys select from.
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

    /// The most answers in a row that mail alone starts in the session of a
    /// run, with no caller message between them. Message mail and final
    /// messages both count. When the Router holds the mail at this limit,
    /// the run fails with ``AgentRunFailure/mailDeliveryPaused(_:)``.
    ///
    /// The default is the default of the Router,
    /// `SessionConfiguration.defaultMailOnlyAnswerLimit`.
    var mailOnlyAnswerLimit = SessionConfiguration.defaultMailOnlyAnswerLimit

    /// Makes an environment.
    ///
    /// A value out of its range is a programmer error and stops the process.
    ///
    /// - Parameters:
    ///   - profile: The resolved profile of the host.
    ///   - skills: The skills registry of the host.
    ///   - workingDirectory: The working directory of each run. The default
    ///     is the current directory of the process.
    ///   - tools: The tool catalog. The default is an empty catalog.
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
    public init(
        profile: LanguageModelProfile,
        skills: SkillsRegistry,
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
        inlineSettleGrace: TimeInterval = ToolMount.defaultInlineSettleGrace
    ) {
        precondition(
            ModelMatch.generationSlots.contains { $0.slot == defaultSlot },
            "defaultSlot must be .standard or .flash")
        precondition(maxConcurrentAgents >= 1, "maxConcurrentAgents must be one or more")
        precondition(maxDepth >= 1, "maxDepth must be one or more")
        precondition(maxRetainedRuns >= 0, "maxRetainedRuns must be zero or more")
        self.profile = profile
        self.skills = skills
        self.workingDirectory = workingDirectory
        self.tools = tools
        self.defaultSlot = defaultSlot
        self.maxConcurrentAgents = maxConcurrentAgents
        self.maxDepth = maxDepth
        self.maxRetainedRuns = maxRetainedRuns
        self.budget = budget
        self.tracer = tracer
        self.logger = logger
        self.metricsFactory = metricsFactory
        self.inlineSettleGrace = max(0, inlineSettleGrace)
    }
}
