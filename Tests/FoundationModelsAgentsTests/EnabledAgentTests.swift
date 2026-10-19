import FoundationModelsExtras
import Testing

@testable import FoundationModelsAgents

/// Pins the `enabled` key of an agent file.
///
/// `enabled: false` turns an agent off: it is gone from each surface of the
/// model and the user (the catalog, the `agents` tool, `find agents`, and the
/// slash commands), and only one diagnostic of the catalog names it. A value
/// that is not `true` or `false` fails closed. FoundationModelsExtras reads the
/// key (`FrontmatterEnablement`). The scan of Agents applies it after its own
/// shadowing: the nearest copy wins, and when it is off, the agent is off.
@Suite("The enabled key of an agent")
struct EnabledAgentTests {
    /// The agent that stays on in each row.
    private static let onAgent = "on-agent"

    /// The agent that a row turns off.
    private static let offAgent = "off-agent"

    /// The description of each agent file.
    private static let description = "Checks the text."

    /// The text of an agent file on the `flash` slot.
    ///
    /// - Parameters:
    ///   - name: The id of the agent.
    ///   - enabled: The `enabled` line, or `nil` for no such key.
    /// - Returns: The file text.
    private static func agentFile(_ name: String, enabled: String? = nil) -> String {
        let enabledLine = enabled.map { "enabled: \($0)\n" } ?? ""
        return """
            ---
            name: \(name)
            description: \(description)
            model: flash
            \(enabledLine)---
            You check the text.
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

    /// Loads a registry over `layers`, lowest precedence first.
    ///
    /// - Parameter layers: The layers.
    /// - Returns: The loaded catalog.
    /// - Throws: The error of the load.
    private static func catalog(of layers: [TemporaryLayer]) async throws -> AgentCatalog {
        let registry = AgentRegistry(layers: layers.map(\.layer))
        try await registry.load()
        return registry.catalog()
    }

    /// The diagnostics of `catalog` that name `agent`.
    ///
    /// - Parameters:
    ///   - catalog: The catalog.
    ///   - agent: The id of the agent.
    /// - Returns: The diagnostics of the agent.
    private static func diagnostics(of agent: String, in catalog: AgentCatalog) -> [AgentDiagnostic] {
        catalog.diagnostics.filter { $0.agent == agent }
    }

    @Test("enabled: false leaves the agent out of the catalog, with one skip that tells why")
    func disabledAgentIsNotInTheCatalog() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.write(Self.onAgent, in: layer)
        try Self.write(Self.offAgent, in: layer, enabled: "false")

        let catalog = try await Self.catalog(of: [layer])
        let diagnostics = Self.diagnostics(of: Self.offAgent, in: catalog)

        #expect(catalog.definitions.map(\.id) == [Self.onAgent])
        #expect(diagnostics.map(\.severity) == [.skip])
        #expect(diagnostics.map(\.message) == [AgentCatalogBuilder.disabledMessage])
    }

    @Test("enabled: true loads the agent, and the key is not an unknown key")
    func enabledTrueIsAKnownKey() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.write(Self.onAgent, in: layer, enabled: "true")

        let catalog = try await Self.catalog(of: [layer])

        #expect(catalog.definitions.map(\.id) == [Self.onAgent])
        #expect(Self.diagnostics(of: Self.onAgent, in: catalog).isEmpty)
    }

    @Test("an enabled value that is not true or false fails closed, with one skip", arguments: [#""false""#, "0", "[no]"])
    func invalidValueFailsClosed(value: String) async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.write(Self.offAgent, in: layer, enabled: value)

        let catalog = try await Self.catalog(of: [layer])
        let diagnostics = Self.diagnostics(of: Self.offAgent, in: catalog)

        #expect(catalog.definitions.isEmpty)
        #expect(diagnostics.map(\.severity) == [.skip])
        #expect(diagnostics.first?.message.contains(FrontmatterEnablement.key) == true)
    }

    @Test("a nearer stub with only enabled: false turns off the agent of a farther layer, with no decode noise")
    func nearerDisabledCopyWins() async throws {
        let far = try TemporaryLayer.makeEmpty()
        let near = try TemporaryLayer.makeEmpty()
        defer {
            try? far.delete()
            try? near.delete()
        }
        try Self.write(Self.offAgent, in: far)
        try near.write("---\nenabled: false\n---\n", at: AgentDocumentPath.of(Self.offAgent))

        let catalog = try await Self.catalog(of: [far, near])
        let diagnostics = Self.diagnostics(of: Self.offAgent, in: catalog)

        #expect(catalog.definitions.isEmpty)
        #expect(diagnostics.map(\.severity) == [.skip, .advisory], "the skip, then the advisory of the hidden copy")
        #expect(diagnostics.first?.message == AgentCatalogBuilder.disabledMessage)
    }

    @Test("a nearer enabled copy wins over a farther disabled copy")
    func nearerEnabledCopyWins() async throws {
        let far = try TemporaryLayer.makeEmpty()
        let near = try TemporaryLayer.makeEmpty()
        defer {
            try? far.delete()
            try? near.delete()
        }
        try Self.write(Self.onAgent, in: far, enabled: "false")
        try Self.write(Self.onAgent, in: near)

        let catalog = try await Self.catalog(of: [far, near])

        #expect(catalog.definitions.map(\.id) == [Self.onAgent])
    }

    @Test("a disabled agent is not in the tool description, list agents, or find agents, and start agent corrects it")
    func disabledAgentIsGoneFromTheTool() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.write(Self.onAgent, in: layer)
        try Self.write(Self.offAgent, in: layer, enabled: "false")
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }

        let listed = try await harness.call("list agents")
        let found = try await harness.call("find agents", ["query": Self.description])
        let started = try await harness.call("start agent", ["name": Self.offAgent, "prompt": "check the text"])

        #expect(!harness.tool.description.contains(Self.offAgent))
        #expect(!listed.contains(Self.offAgent))
        #expect(!found.contains(Self.offAgent))
        #expect(started == AgentsToolText.unknownAgent(Self.offAgent, available: [Self.onAgent]))
        #expect(await harness.runner.runs.isEmpty)
    }

    @Test("a disabled agent is not a slash command")
    func disabledAgentIsNotASlashCommand() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.write(Self.onAgent, in: layer)
        try Self.write(Self.offAgent, in: layer, enabled: "false")
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([]), registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }

        let names = await harness.makeRunner().commands(workingDirectory: harness.workingDirectory).map(\.name)

        #expect(names == [Self.onAgent])
    }
}
