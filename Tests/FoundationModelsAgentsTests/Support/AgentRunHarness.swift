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
        AgentEnvironment(
            profile: profile, skills: SkillsRegistry(roots: []), workingDirectory: workingDirectory,
            budget: budget)
    }

    /// Makes a harness.
    ///
    /// - Parameters:
    ///   - script: The script that each slot of the profile plays.
    ///   - registry: The registry to load. The default is the fixture
    ///     library.
    ///   - budget: Makes the budget of each run. The default is
    ///     `AgentEnvironment.defaultBudget`.
    /// - Returns: The harness.
    /// - Throws: The error of the file system, of the profile, or of
    ///   `registry.load()`.
    static func make(
        script: ScriptedAgentScript,
        registry: AgentRegistry = AgentRegistry(stack: FixtureLibrary.stack()),
        budget: @escaping AgentEnvironment.BudgetFactory = AgentEnvironment.defaultBudget
    ) async throws -> AgentRunHarness {
        let scratch = try TemporaryLayer.makeEmpty()
        try scratch.write(agentsMdText, at: agentsMdName)
        let (router, profile) = try await ScriptedProfile.make(
            script: script,
            recordingsDir: scratch.container.appendingPathComponent(recordingsFolderName, isDirectory: true))
        try await registry.load()
        return AgentRunHarness(
            router: router, profile: profile, script: script, registry: registry, budget: budget,
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
        agentsTool: ToolResolver.AgentsToolFactory? = nil
    ) async throws -> AgentRun {
        let definition = try #require(registry.catalog().definition(named: agent))
        let environment = environment
        let request = AgentRunRequest(
            definition: definition, prompt: prompt, context: context,
            inheritedSlot: environment.defaultSlot, depth: 1, agentsTool: agentsTool)
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
