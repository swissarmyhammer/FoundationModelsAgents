import Foundation
import FoundationModelsRouter
import FoundationModelsSkills

/// The dependencies and the limits of the agent runs of one host
/// (plan.md §3, §7).
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

    /// The default of ``maxDepth`` (plan.md §1).
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
    public init(
        profile: LanguageModelProfile,
        skills: SkillsRegistry,
        workingDirectory: URL = URL.currentDirectory(),
        tools: ToolCatalog = ToolCatalog(),
        defaultSlot: ModelSlot = .standard,
        maxConcurrentAgents: Int = defaultMaxConcurrentAgents,
        maxDepth: Int = defaultMaxDepth,
        maxRetainedRuns: Int = defaultMaxRetainedRuns,
        budget: @escaping BudgetFactory = defaultBudget
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
    }
}
