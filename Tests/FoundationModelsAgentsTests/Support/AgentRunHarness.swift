import Foundation
@testable import FoundationModelsAgents
import FoundationModelsRouter
import FoundationModelsSkills
import Testing

/// The parts of one `AgentRun` test: a scripted profile that records to a
/// temporary folder, a working directory that holds one `AGENTS.md`, and a
/// loaded registry.
///
/// Each harness has its own folders, thus tests that run in parallel do not
/// share files. The test calls `delete()` in a `defer`.
struct AgentRunHarness {
    /// The name of the agent-instructions file in the working directory.
    static let agentsMdName = "AGENTS.md"

    /// The text of the `AGENTS.md` file of the working directory.
    static let agentsMdText = "Project note from AGENTS.md: keep each change small."

    /// The name of the recordings folder in the scratch container.
    static let recordingsFolderName = "recordings"

    /// The router of the scripted profile.
    let router: Router

    /// The scripted profile.
    let profile: LanguageModelProfile

    /// The script that each slot of the profile plays.
    let script: ScriptedAgentScript

    /// The registry that gives the definitions. It is loaded.
    let registry: AgentRegistry

    /// The skills registry of each run. The `skills:` preload reads it.
    let skills: SkillsRegistry

    /// Makes the budget of each run.
    let budget: AgentEnvironment.BudgetFactory

    /// The scratch folder. Its root is the working directory of each run.
    let scratch: TemporaryLayer

    /// The working directory of each run. It holds `AGENTS.md`.
    var workingDirectory: URL {
        scratch.root
    }

    /// The recordings root of the router.
    var recordingsDirectory: URL {
        scratch.container.appendingPathComponent(Self.recordingsFolderName, isDirectory: true)
    }

    /// The folder of the sessions of the router: `<recordingsDir>/<routerId>`.
    var sessionsDirectory: URL {
        recordingsDirectory.appendingPathComponent(router.id.description, isDirectory: true)
    }

    /// The environment of each run.
    var environment: AgentEnvironment {
        environment(maxRetainedRuns: AgentEnvironment.defaultMaxRetainedRuns)
    }

    /// Makes the environment of each run with a count of retained records,
    /// a run limit, and a depth limit.
    ///
    /// - Parameters:
    ///   - maxRetainedRuns: The count of finished run records that a runner
    ///     keeps.
    ///   - maxConcurrentAgents: The count of runs that `start agent` lets
    ///     work at one time. The default is
    ///     `AgentEnvironment.defaultMaxConcurrentAgents`.
    ///   - maxDepth: The depth limit of the runs. The default is
    ///     `AgentEnvironment.defaultMaxDepth`.
    /// - Returns: The environment.
    func environment(
        maxRetainedRuns: Int,
        maxConcurrentAgents: Int = AgentEnvironment.defaultMaxConcurrentAgents,
        maxDepth: Int = AgentEnvironment.defaultMaxDepth
    ) -> AgentEnvironment {
        AgentEnvironment(
            profile: profile, skills: skills, workingDirectory: workingDirectory,
            maxConcurrentAgents: maxConcurrentAgents, maxDepth: maxDepth, maxRetainedRuns: maxRetainedRuns,
            budget: budget)
    }

    /// Makes a runner over the registry and the environment of the harness.
    ///
    /// - Parameters:
    ///   - maxRetainedRuns: The count of finished run records that the
    ///     runner keeps. The default is
    ///     `AgentEnvironment.defaultMaxRetainedRuns`.
    ///   - maxConcurrentAgents: The count of runs that `start agent` lets
    ///     work at one time. The default is
    ///     `AgentEnvironment.defaultMaxConcurrentAgents`.
    ///   - maxDepth: The depth limit of the runs. The default is
    ///     `AgentEnvironment.defaultMaxDepth`.
    /// - Returns: The runner.
    func makeRunner(
        maxRetainedRuns: Int = AgentEnvironment.defaultMaxRetainedRuns,
        maxConcurrentAgents: Int = AgentEnvironment.defaultMaxConcurrentAgents,
        maxDepth: Int = AgentEnvironment.defaultMaxDepth
    ) -> AgentRunner {
        AgentRunner(
            registry: registry,
            environment: environment(
                maxRetainedRuns: maxRetainedRuns, maxConcurrentAgents: maxConcurrentAgents, maxDepth: maxDepth))
    }

    /// Makes a harness.
    ///
    /// - Parameters:
    ///   - script: The script that each slot of the profile plays.
    ///   - registry: The registry to load. The default is the fixture
    ///     library.
    ///   - skills: The skills registry of each run. The default has no
    ///     layers.
    ///   - budget: Makes the budget of each run. The default is
    ///     `AgentEnvironment.defaultBudget`.
    /// - Returns: The harness.
    /// - Throws: The error of the file system, of the profile, or of
    ///   `registry.load()`.
    static func make(
        script: ScriptedAgentScript,
        registry: AgentRegistry = AgentRegistry(stack: FixtureLibrary.stack()),
        skills: SkillsRegistry = SkillsRegistry(roots: []),
        budget: @escaping AgentEnvironment.BudgetFactory = AgentEnvironment.defaultBudget
    ) async throws -> AgentRunHarness {
        let scratch = try TemporaryLayer.makeEmpty()
        try scratch.write(agentsMdText, at: agentsMdName)
        let (router, profile) = try await ScriptedProfile.make(
            script: script,
            recordingsDir: scratch.container.appendingPathComponent(recordingsFolderName, isDirectory: true))
        try await registry.load()
        return AgentRunHarness(
            router: router, profile: profile, script: script, registry: registry, skills: skills, budget: budget,
            scratch: scratch)
    }

    /// Starts a host-started run of `agent` with `prompt`.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent in the registry.
    ///   - prompt: The prompt of the run.
    ///   - context: The context of the tool call that starts the run, or
    ///     `nil` for a host-driven run.
    ///   - agentsTool: Makes the `agents` tool, or `nil`.
    /// - Returns: The run, when `start` returns.
    /// - Throws: The error of `#require` when the registry has no such agent.
    func start(
        _ agent: String,
        prompt: String,
        context: ToolContext? = nil,
        agentsTool: AgentRunRequest.AgentsToolMaker? = nil
    ) async throws -> AgentRun {
        let definition = try #require(registry.catalog().definition(named: agent))
        let environment = environment
        let request = AgentRunRequest(
            definition: definition, prompt: prompt, context: context,
            inheritedSlot: environment.defaultSlot, depth: AgentRunner.hostDepth, parent: nil,
            agentsTool: agentsTool)
        return await AgentRun.start(
            request, environment: environment, renderer: AgentBodyRenderer(registry: registry))
    }

    /// Removes the folders of the harness.
    ///
    /// - Throws: The error of the file system.
    func delete() throws {
        try scratch.delete()
    }
}
