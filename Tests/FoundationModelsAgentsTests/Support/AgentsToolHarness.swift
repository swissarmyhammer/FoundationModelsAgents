import FoundationModels
import FoundationModelsRouter
import FoundationModelsSkills
import Logging
import Metrics
import Tracing

@testable import FoundationModelsAgents

/// An `agents` tool that `AgentsTool.make` made over a loaded registry, and
/// the run harness that holds its runner.
///
/// The tests of the tool surface read the description and the schema, and
/// start no run: their script is empty. The tests of the operations give a
/// script with a play for each run and each root session. The test calls
/// `delete()` in a `defer`.
struct AgentsToolHarness {
    /// The run harness that holds the profile and the registry of the runner.
    let runHarness: AgentRunHarness

    /// The runner that owns each run that the tool starts.
    let runner: AgentRunner

    /// The tool that `AgentsTool.make` made.
    let tool: AgentsTool

    /// Loads `registry`, makes a runner over it, and makes the tool.
    ///
    /// - Parameters:
    ///   - script: The script that each slot of the profile plays. The
    ///     default is an empty script.
    ///   - registry: The registry of the runner. The default is the fixture
    ///     library.
    ///   - allowedNames: The names of `Agent(a, b)`, or `nil` for all agents.
    ///   - catalogCharacterLimit: The most characters that the agent list of
    ///     the description can have.
    ///   - maxConcurrentAgents: The count of runs that `start agent` lets
    ///     work at one time. The default is
    ///     `AgentEnvironment.defaultMaxConcurrentAgents`.
    ///   - grant: The operations that the tool gives. The default is
    ///     `.full`.
    ///   - telemetry: The tracer, the logger and the metrics factory of the
    ///     router and of each run. The default has none of them.
    /// - Returns: The harness.
    /// - Throws: The error of the run harness, or of `AgentsTool.make`.
    static func make(
        script: ScriptedAgentScript = ScriptedAgentScript([]),
        registry: AgentRegistry = AgentRegistry(stack: FixtureLibrary.stack()),
        allowedNames: [String]? = nil,
        catalogCharacterLimit: Int = SkillsTool.defaultCatalogCharacterLimit,
        maxConcurrentAgents: Int = AgentEnvironment.defaultMaxConcurrentAgents,
        grant: AgentsToolContext.Grant = .full,
        telemetry: HarnessTelemetry = HarnessTelemetry()
    ) async throws -> AgentsToolHarness {
        let runHarness = try await AgentRunHarness.make(
            script: script, registry: registry, tracer: telemetry.tracer, logger: telemetry.logger,
            metricsFactory: telemetry.metricsFactory)
        let runner = runHarness.makeRunner(maxConcurrentAgents: maxConcurrentAgents)
        let context = AgentsToolContext(
            runner: runner, allowedNames: allowedNames, parent: nil, callerLink: nil, grant: grant)
        do {
            let tool = try await AgentsTool.make(context: context, catalogCharacterLimit: catalogCharacterLimit)
            return AgentsToolHarness(runHarness: runHarness, runner: runner, tool: tool)
        } catch {
            try? runHarness.delete()
            throw error
        }
    }

    /// Makes the tool over an empty layer: a catalog with no agent.
    ///
    /// - Returns: The harness and the empty layer. The test deletes both.
    /// - Throws: The error of the file system, or of `make`.
    static func makeEmpty() async throws -> (harness: AgentsToolHarness, layer: TemporaryLayer) {
        let layer = try TemporaryLayer.makeEmpty()
        do {
            return (try await make(registry: AgentRegistry(layers: [layer.layer])), layer)
        } catch {
            try? layer.delete()
            throw error
        }
    }

    /// Calls the tool with the op `operation` and the fields `fields`, as a
    /// model does, outside a Router session.
    ///
    /// - Parameters:
    ///   - operation: The `op` of the payload, for example `start agent`.
    ///   - fields: The other fields of the payload.
    /// - Returns: The answer of the tool.
    /// - Throws: The error of `AgentsTool.call(arguments:)`.
    func call(_ operation: String, _ fields: [String: String] = [:]) async throws -> String {
        let properties = fields.merging(["op": operation]) { _, operation in operation }
            .lazy.map { field -> (String, any ConvertibleToGeneratedContent) in (field.key, field.value) }
        return try await tool.call(
            arguments: GeneratedContent(properties: Array(properties), uniquingKeysWith: { _, last in last }))
    }

    /// Removes the folders of the run harness.
    ///
    /// - Throws: The error of the file system.
    func delete() throws {
        try runHarness.delete()
    }
}

/// The telemetry that a test gives to ``AgentsToolHarness/make(script:registry:allowedNames:catalogCharacterLimit:maxConcurrentAgents:grant:telemetry:)``.
///
/// A test that reads the telemetry of a root session or of a child run gives
/// the telemetry of its capture here. The pump of a session is a detached
/// task, which does not inherit the task-local values of the capture.
struct HarnessTelemetry {
    /// The tracer of the router and of each run, or `nil` for
    /// `InstrumentationSystem.tracer` at call time.
    var tracer: (any Tracer)?

    /// The logger of each run, or `nil` for a new logger for each run.
    var logger: Logger?

    /// The metrics factory of each run, or `nil` for `MetricsSystem.factory`.
    var metricsFactory: (any MetricsFactory)?
}
