import FoundationModelsSkills

@testable import FoundationModelsAgents

/// An `agents` tool that `AgentsTool.make` made over a loaded registry, and
/// the run harness that holds its runner.
///
/// The tests of the tool surface read the description and the schema. They
/// start no run, thus the script of the profile is empty. The test calls
/// `delete()` in a `defer`.
struct AgentsToolHarness {
    /// The run harness that holds the profile and the registry of the runner.
    let runHarness: AgentRunHarness

    /// The tool that `AgentsTool.make` made.
    let tool: AgentsTool

    /// Loads `registry`, makes a runner over it, and makes the tool.
    ///
    /// - Parameters:
    ///   - registry: The registry of the runner. The default is the fixture
    ///     library.
    ///   - allowedNames: The names of `Agent(a, b)`, or `nil` for all agents.
    ///   - catalogCharacterLimit: The most characters that the agent list of
    ///     the description can have.
    /// - Returns: The harness.
    /// - Throws: The error of the run harness, or of `AgentsTool.make`.
    static func make(
        registry: AgentRegistry = AgentRegistry(stack: FixtureLibrary.stack()),
        allowedNames: [String]? = nil,
        catalogCharacterLimit: Int = SkillsTool.defaultCatalogCharacterLimit
    ) async throws -> AgentsToolHarness {
        let runHarness = try await AgentRunHarness.make(script: ScriptedAgentScript([]), registry: registry)
        let context = AgentsToolContext(runner: runHarness.makeRunner(), allowedNames: allowedNames)
        do {
            let tool = try await AgentsTool.make(context: context, catalogCharacterLimit: catalogCharacterLimit)
            return AgentsToolHarness(runHarness: runHarness, tool: tool)
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

    /// Removes the folders of the run harness.
    ///
    /// - Throws: The error of the file system.
    func delete() throws {
        try runHarness.delete()
    }
}
