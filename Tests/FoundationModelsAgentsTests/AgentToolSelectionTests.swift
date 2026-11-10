import FoundationModels
@testable import FoundationModelsAgents
import Testing

/// Pins `AgentDefinition.toolSelection(over:hasAgentsTool:)`: the tool
/// selection of a run as a public API, with the same rules as
/// `ToolResolver`.
@Suite("Agent tool selection")
struct AgentToolSelectionTests {
    /// One pair of `tools` and `disallowedTools` lines, as the frontmatter
    /// writes them.
    struct ListRow: Sendable, CustomTestStringConvertible {
        /// The frontmatter lines of the two keys. An empty text gives no key.
        let yaml: String

        /// The lines, as the name of the test case.
        var testDescription: String {
            yaml.isEmpty ? "no keys" : yaml
        }
    }

    /// The first tool of the MCP server `srv`.
    static let srvFirst = "mcp__srv__a"

    /// The second tool of the MCP server `srv`.
    static let srvSecond = "mcp__srv__b"

    /// A tool of the MCP server `srv2`. Its name starts with `mcp__srv`, but
    /// it is not a tool of the server `srv`.
    static let srv2Tool = "mcp__srv2__a"

    /// The names of three MCP tools of two servers.
    static let mcpNames = [srvFirst, srvSecond, srv2Tool]

    /// The pairs of lists that the parity test resolves in two ways.
    static let parityRows: [ListRow] = [
        ListRow(yaml: ""),
        ListRow(yaml: "tools: \(ToolResolverTests.read)"),
        ListRow(yaml: "tools: \(ToolResolverTests.read), \(ToolResolverTests.unknown)"),
        ListRow(yaml: "disallowedTools: \(ToolResolverTests.grep)"),
        ListRow(yaml: "disallowedTools: \(ToolResolverTests.unknown)"),
        ListRow(yaml: "tools: mcp__srv, \(ToolResolverTests.read)\ndisallowedTools: \(ToolResolverTests.srvFirst)"),
        ListRow(yaml: "tools: mcp__*"),
        ListRow(yaml: "tools: Agent(\(ToolResolverTests.firstAgent), \(ToolResolverTests.secondAgent))"),
        ListRow(yaml: "tools: Agent, \(ToolResolverTests.read)\ndisallowedTools: Agent"),
        ListRow(yaml: "tools: \(ToolResolverTests.agentsName), \(ToolResolverTests.unknown)\ndisallowedTools: mcp__other")
    ]

    /// Decodes one inline definition with a valid description.
    ///
    /// - Parameter yaml: The frontmatter lines after the description.
    /// - Returns: The definition.
    /// - Throws: An error when the frontmatter gives no definition.
    static func definition(_ yaml: String) throws -> AgentDefinition {
        try #require(AgentDefinitionAttempt.inline("\(AgentDefinitionAttempt.validDescription)\n\(yaml)").definition)
    }

    @Test("toolSelection gives the names, the grant and the diagnostics of a run", arguments: parityRows)
    func selectionMatchesTheRunPath(row: ListRow) async throws {
        let definition = try Self.definition(row.yaml)
        let calls = ToolResolverTests.AgentsToolCalls()
        let resolved = try await ToolResolver(agent: definition.id, provenance: definition.provenance).resolve(
            tools: definition.tools?.map(ToolSpec.parse),
            disallowed: definition.disallowedTools.map(ToolSpec.parse),
            catalog: ToolResolverTests.makeCatalog(),
            agentsTool: ToolResolverTests.makeAgentsTool(recordingIn: calls))

        let selection = definition.toolSelection(over: ToolResolverTests.catalogNames, hasAgentsTool: true)

        #expect(resolved.tools.map(\.name).filter { $0 != ToolResolverTests.agentsName } == selection.names)
        #expect(await calls.grants == (selection.deniesAgents ? [] : [selection.agentsGrant]))
        #expect(resolved.diagnostics == selection.diagnostics)
    }

    @Test("no tools key gives each name")
    func noToolsKeyGivesEachName() throws {
        let selection = try Self.definition("").toolSelection(
            over: ToolResolverTests.catalogNames, hasAgentsTool: false)

        #expect(selection.names == ToolResolverTests.catalogNames)
    }

    @Test("disallowedTools removes the names that it matches")
    func disallowedToolsRemovesNames() throws {
        let selection = try Self.definition("disallowedTools: \(ToolResolverTests.grep)").toolSelection(
            over: ToolResolverTests.catalogNames, hasAgentsTool: false)

        #expect(selection.names == ToolResolverTests.catalogNames.filter { $0 != ToolResolverTests.grep })
    }

    @Test("an unknown entry gives one warning")
    func unknownEntryGivesOneWarning() throws {
        let selection = try Self.definition("tools: \(ToolResolverTests.read), \(ToolResolverTests.unknown)")
            .toolSelection(over: ToolResolverTests.catalogNames, hasAgentsTool: false)

        #expect(selection.diagnostics.map(\.severity) == [.warning])
    }

    @Test("mcp__srv matches the tools of srv and not the tools of srv2")
    func serverEntryMatchesOnlyItsServer() throws {
        let selection = try Self.definition("tools: mcp__srv").toolSelection(
            over: Self.mcpNames, hasAgentsTool: false)

        #expect(selection.names == [Self.srvFirst, Self.srvSecond])
    }

    @Test("the all-servers entry matches each MCP name")
    func allServersEntryMatchesEachMCPName() throws {
        let selection = try Self.definition("tools: mcp__*").toolSelection(
            over: [ToolResolverTests.read] + Self.mcpNames, hasAgentsTool: false)

        #expect(selection.names == Self.mcpNames.sorted())
    }

    @Test("Agent(a, b) gives a grant of only a and b with the agents tool")
    func agentListGivesOnlyGrant() throws {
        let selection = try Self.definition(
            "tools: Agent(\(ToolResolverTests.firstAgent), \(ToolResolverTests.secondAgent))"
        ).toolSelection(over: ToolResolverTests.catalogNames, hasAgentsTool: true)

        #expect(selection.agentsGrant == .only([ToolResolverTests.firstAgent, ToolResolverTests.secondAgent]))
    }

    @Test("Agent(a, b) gives one warning with no agents tool")
    func agentListWithNoAgentsToolGivesWarning() throws {
        let selection = try Self.definition(
            "tools: Agent(\(ToolResolverTests.firstAgent), \(ToolResolverTests.secondAgent))"
        ).toolSelection(over: ToolResolverTests.catalogNames, hasAgentsTool: false)

        #expect(selection.diagnostics.map(\.code) == [.unknownTool])
    }

    @Test("Agent in disallowedTools denies the agents tool")
    func disallowedAgentDeniesAgents() throws {
        let selection = try Self.definition("tools: Agent\ndisallowedTools: Agent").toolSelection(
            over: ToolResolverTests.catalogNames, hasAgentsTool: true)

        #expect(selection.deniesAgents)
    }

    @Test("Agent in disallowedTools gives no grant")
    func disallowedAgentGivesNoGrant() throws {
        let selection = try Self.definition("tools: Agent\ndisallowedTools: Agent").toolSelection(
            over: ToolResolverTests.catalogNames, hasAgentsTool: true)

        #expect(selection.agentsGrant == nil)
    }

    @Test("the entry agents gives a grant and never puts agents into the names")
    func agentsEntryIsNotAName() throws {
        let selection = try Self.definition("tools: \(ToolResolverTests.agentsName)").toolSelection(
            over: [ToolResolverTests.agentsName, ToolResolverTests.read], hasAgentsTool: true)

        #expect(selection.names.isEmpty)
    }
}
