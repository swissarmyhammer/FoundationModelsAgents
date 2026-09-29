import Foundation
@testable import FoundationModelsAgents
import FoundationModelsRouter
import FoundationModelsSkills
import Logging
import Metrics
import Testing
import Tracing

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

    /// The tool catalog of each run. The `tools` key of an agent selects
    /// from it.
    let tools: ToolCatalog

    /// The tracer of the router and of each run, or `nil` for
    /// `InstrumentationSystem.tracer` at call time.
    let tracer: (any Tracer)?

    /// The logger of each run, or `nil` for a new
    /// `Logger(label: AgentsTelemetry.logLabel)` for each run.
    let logger: Logger?

    /// The metrics factory of each run, or `nil` for `MetricsSystem.factory`
    /// when each run ends.
    let metricsFactory: (any MetricsFactory)?

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
            profile: profile, skills: skills, workingDirectory: workingDirectory, tools: tools,
            maxConcurrentAgents: maxConcurrentAgents, maxDepth: maxDepth, maxRetainedRuns: maxRetainedRuns,
            budget: budget, tracer: tracer, logger: logger, metricsFactory: metricsFactory)
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
    ///   - tools: The tool catalog of each run. The default is an empty
    ///     catalog.
    ///   - tracer: The tracer of the router and of each run, or `nil` (the
    ///     default) for `InstrumentationSystem.tracer` at call time. A test
    ///     that reads the spans of the sessions gives its tracer here,
    ///     because the pump of a session does not inherit a task-local
    ///     tracer.
    ///   - logger: The logger of each run, or `nil` (the default) for a new
    ///     `Logger(label: AgentsTelemetry.logLabel)` for each run. A test
    ///     that reads the log records of a child run gives its logger here,
    ///     because a child run starts under the detached pump of a session,
    ///     which does not inherit the log capture of the test.
    ///   - metricsFactory: The metrics factory of each run, or `nil` (the
    ///     default) for `MetricsSystem.factory` when each run ends. A test
    ///     that reads the metrics of a child run gives its factory here,
    ///     because a child run starts under the detached pump of a session,
    ///     which does not inherit the task-local factory of the test.
    /// - Returns: The harness.
    /// - Throws: The error of the file system, of the profile, or of
    ///   `registry.load()`.
    static func make(
        script: ScriptedAgentScript,
        registry: AgentRegistry = AgentRegistry(stack: FixtureLibrary.stack()),
        skills: SkillsRegistry = SkillsRegistry(roots: []),
        budget: @escaping AgentEnvironment.BudgetFactory = AgentEnvironment.defaultBudget,
        tools: ToolCatalog = ToolCatalog(),
        tracer: (any Tracer)? = nil,
        logger: Logger? = nil,
        metricsFactory: (any MetricsFactory)? = nil
    ) async throws -> AgentRunHarness {
        let scratch = try TemporaryLayer.makeEmpty()
        try scratch.write(agentsMdText, at: agentsMdName)
        let (router, profile) = try await ScriptedProfile.make(
            script: script,
            recordingsDir: scratch.container.appendingPathComponent(recordingsFolderName, isDirectory: true),
            tracer: tracer)
        try await registry.load()
        return AgentRunHarness(
            router: router, profile: profile, script: script, registry: registry, skills: skills, budget: budget,
            tools: tools, tracer: tracer, logger: logger, metricsFactory: metricsFactory, scratch: scratch)
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
