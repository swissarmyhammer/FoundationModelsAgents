import FoundationModels
import FoundationModelsSkills

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
    /// - Returns: The harness.
    /// - Throws: The error of the run harness, or of `AgentsTool.make`.
    static func make(
        script: ScriptedAgentScript = ScriptedAgentScript([]),
        registry: AgentRegistry = AgentRegistry(stack: FixtureLibrary.stack()),
        allowedNames: [String]? = nil,
        catalogCharacterLimit: Int = SkillsTool.defaultCatalogCharacterLimit
    ) async throws -> AgentsToolHarness {
        let runHarness = try await AgentRunHarness.make(script: script, registry: registry)
        let runner = runHarness.makeRunner()
        let context = AgentsToolContext(runner: runner, allowedNames: allowedNames)
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
