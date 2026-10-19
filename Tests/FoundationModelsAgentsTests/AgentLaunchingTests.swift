import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsAgents

/// Pins the `AgentLaunching` conformance of the `agents` tool.
///
/// A host casts each tool of a session to `AgentLaunching` and reads the
/// agents that the tool can start now, for example to name an agent in a
/// hint. The list is the startable set of the tool: the agents of the current
/// catalog that its grant allows, in catalog order, each with its description
/// on one line. A tool with only the message operations starts none.
@Suite("The agents tool is AgentLaunching")
struct AgentLaunchingTests {
    /// The first agent of the layer.
    private static let coder = "coder"

    /// The second agent of the layer.
    private static let reviewer = "reviewer"

    /// The agent that a row adds or turns off.
    private static let extra = "extra"

    /// The description of an agent: two lines, thus the entry shows one line.
    ///
    /// - Parameter name: The id of the agent.
    /// - Returns: The description of the frontmatter, as a YAML block.
    private static func description(of name: String) -> String {
        "Does the work of \(name).\n  It works well."
    }

    /// The description that an entry of `name` gives: on one line.
    ///
    /// - Parameter name: The id of the agent.
    /// - Returns: The one-line description.
    private static func entryDescription(of name: String) -> String {
        "Does the work of \(name). It works well."
    }

    /// The text of an agent file on the `flash` slot.
    ///
    /// - Parameters:
    ///   - name: The id of the agent.
    ///   - enabled: The `enabled` value, or `nil` for no such key.
    /// - Returns: The file text.
    private static func agentFile(_ name: String, enabled: String? = nil) -> String {
        let enabledLine = enabled.map { "enabled: \($0)\n" } ?? ""
        return """
            ---
            name: \(name)
            description: >-
              \(description(of: name))
            model: flash
            \(enabledLine)---
            You do the work.
            """
    }

    /// Writes the file of the agent `name` into `layer`.
    ///
    /// - Parameters:
    ///   - name: The id of the agent.
    ///   - layer: The layer.
    ///   - enabled: The `enabled` value, or `nil` for no such key.
    /// - Throws: The error of the file system.
    private static func write(_ name: String, in layer: TemporaryLayer, enabled: String? = nil) throws {
        try layer.write(agentFile(name, enabled: enabled), at: AgentDocumentPath.of(name))
    }

    /// Makes a layer with ``coder`` and ``reviewer``.
    ///
    /// - Returns: The layer. The test deletes it.
    /// - Throws: The error of the file system.
    private static func makeLayer() throws -> TemporaryLayer {
        let layer = try TemporaryLayer.makeEmpty()
        do {
            try write(coder, in: layer)
            try write(reviewer, in: layer)
            return layer
        } catch {
            try? layer.delete()
            throw error
        }
    }

    /// Casts `tool` to `AgentLaunching` as a host does, and reads its list.
    ///
    /// - Parameter tool: The tool, as a host holds it.
    /// - Returns: The entries of the list.
    private static func launchable(_ tool: any Tool) async throws -> [CatalogEntry] {
        let launching = try #require(tool as? any AgentLaunching)
        return await launching.launchableAgents()
    }

    /// The entry that the list gives for `name`.
    ///
    /// - Parameter name: The id of the agent.
    /// - Returns: The entry.
    private static func entry(_ name: String) -> CatalogEntry {
        CatalogEntry(name: name, description: entryDescription(of: name))
    }

    @Test("the full grant gives each agent of the catalog, in catalog order, each description on one line")
    func fullGrantGivesEachAgent() async throws {
        let layer = try Self.makeLayer()
        defer { try? layer.delete() }
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }

        let entries = try await Self.launchable(harness.tool)

        #expect(entries == [Self.entry(Self.coder), Self.entry(Self.reviewer)])
    }

    @Test("the allowed names of Agent(a, b) limit the list")
    func allowedNamesLimitTheList() async throws {
        let layer = try Self.makeLayer()
        defer { try? layer.delete() }
        let harness = try await AgentsToolHarness.make(
            registry: AgentRegistry(layers: [layer.layer]), allowedNames: [Self.reviewer])
        defer { try? harness.delete() }

        let entries = try await Self.launchable(harness.tool)

        #expect(entries == [Self.entry(Self.reviewer)])
    }

    @Test("the tool of a run does not give the agent of the run")
    func toolOfARunLeavesOutItsOwnAgent() async throws {
        let layer = try Self.makeLayer()
        defer { try? layer.delete() }
        let runHarness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([]), registry: AgentRegistry(layers: [layer.layer]))
        defer { try? runHarness.delete() }
        let parent = ParentRun(
            depth: AgentRunner.hostDepth, slot: .standard, agentID: Self.coder, family: ParentRun.Family(),
            workingDirectory: runHarness.workingDirectory)
        let tool = try await AgentsTool.make(
            context: AgentsToolContext(
                runner: runHarness.makeRunner(), allowedNames: nil, parent: parent, callerLink: nil, grant: .full))

        let entries = try await Self.launchable(tool)

        #expect(entries == [Self.entry(Self.reviewer)])
    }

    @Test("a tool with only the message operations starts no agent")
    func messagingGrantGivesNone() async throws {
        let layer = try Self.makeLayer()
        defer { try? layer.delete() }
        let harness = try await AgentsToolHarness.make(
            registry: AgentRegistry(layers: [layer.layer]), grant: .messagingOnly)
        defer { try? harness.delete() }

        let entries = try await Self.launchable(harness.tool)

        #expect(entries.isEmpty)
    }

    @Test("an empty catalog gives an empty list")
    func emptyCatalogGivesNone() async throws {
        let (harness, layer) = try await AgentsToolHarness.makeEmpty()
        defer {
            try? harness.delete()
            try? layer.delete()
        }

        let entries = try await Self.launchable(harness.tool)

        #expect(entries.isEmpty)
    }

    @Test("after a reload, the list gives an added agent and not an agent that is turned off")
    func listFollowsReloads() async throws {
        let layer = try Self.makeLayer()
        defer { try? layer.delete() }
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }

        try Self.write(Self.extra, in: layer)
        try Self.write(Self.reviewer, in: layer, enabled: "false")
        try await harness.runHarness.registry.reload()
        let entries = try await Self.launchable(harness.tool)

        #expect(entries == [Self.entry(Self.coder), Self.entry(Self.extra)])
    }
}
