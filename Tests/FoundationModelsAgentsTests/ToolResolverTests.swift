import FoundationModels
@testable import FoundationModelsAgents
import Testing

/// Pins `ToolCatalog` and `ToolResolver` (plan.md §5): the Claude semantics
/// of `tools` and `disallowedTools`, the MCP patterns, the unknown names, and
/// the `agents` tool.
@Suite("Tool resolver")
struct ToolResolverTests {
    /// One MCP pattern and the names that it must match.
    struct PatternRow: Sendable, CustomTestStringConvertible {
        /// The entry as the frontmatter writes it.
        let entry: String

        /// The catalog names that the entry must match, in sorted order.
        let expected: [String]

        /// The entry, as the name of the test case.
        var testDescription: String {
            "`\(entry)`"
        }
    }

    /// Records each call of the `agents` tool factory.
    actor AgentsToolCalls {
        /// The grant of each call, in order: `nil` for a call with no
        /// `Agent` entry.
        private(set) var grants: [AgentsGrant?] = []

        /// Records one call.
        ///
        /// - Parameter grant: The grant that the call got.
        func record(_ grant: AgentsGrant?) {
            grants.append(grant)
        }
    }

    /// The name of a plain catalog tool.
    static let read = "Read"

    /// The name of a plain catalog tool.
    static let grep = "Grep"

    /// A name that no catalog holds.
    static let unknown = "NoSuchTool"

    /// The first tool of the MCP server `srv`.
    static let srvFirst = "mcp__srv__first"

    /// The second tool of the MCP server `srv`.
    static let srvSecond = "mcp__srv__second"

    /// A tool of the MCP server `srvx`. Its name starts with `mcp__srv`, but
    /// it is not a tool of the server `srv`.
    static let srvxTool = "mcp__srvx__first"

    /// A tool of the MCP server `other`.
    static let otherTool = "mcp__other__first"

    /// The names of the MCP tools of the catalog, in sorted order.
    static let mcpNames = [otherTool, srvFirst, srvSecond, srvxTool]

    /// The names of the catalog, in sorted order.
    static let catalogNames = [grep, read] + mcpNames

    /// The name of the `agents` tool.
    static let agentsName = "agents"

    /// The first agent name of an `Agent(...)` entry.
    static let firstAgent = "code-reviewer"

    /// The second agent name of an `Agent(...)` entry.
    static let secondAgent = "test-writer"

    /// The id of the agent that the resolver reports on.
    static let agentID = "probe-agent"

    /// The part of the maxDepth warning about a run with a caller.
    static let callerRunMaxDepthPhrase = "a run with a caller gets only the message ops"

    /// The part of the maxDepth warning about a host-started run.
    static let hostStartedMaxDepthPhrase = "a host-started run gets no agents tool"

    /// The resolver of the tests.
    static let resolver = ToolResolver(agent: agentID, provenance: AgentDefinitionAttempt.inlineProvenance)

    /// The MCP patterns of plan.md §5, with the names that each must match.
    static let patternRows: [PatternRow] = [
        PatternRow(entry: "mcp__srv", expected: [srvFirst, srvSecond]),
        PatternRow(entry: "mcp__srv__*", expected: [srvFirst, srvSecond]),
        PatternRow(entry: "mcp__srvx", expected: [srvxTool]),
        PatternRow(entry: "mcp__*", expected: mcpNames)
    ]

    /// Makes a catalog that holds each name of `catalogNames`.
    ///
    /// - Returns: The catalog. Each factory gives a new `ProbeTool`.
    static func makeCatalog() -> ToolCatalog {
        var catalog = ToolCatalog()
        for name in catalogNames {
            catalog.register(name) { ProbeTool(name: name) }
        }
        return catalog
    }

    /// Makes an `agents` tool factory that records each call in `calls`.
    ///
    /// - Parameters:
    ///   - calls: The record of the calls.
    ///   - mountsWithNoGrant: `true` when a call with no grant gives a tool,
    ///     as for a run with a caller. The default is `false`, as for a run
    ///     with no caller.
    /// - Returns: The factory. A call with a grant gives a new `ProbeTool`
    ///   with the name `agents`. A call with no grant gives one only when
    ///   `mountsWithNoGrant` is `true`.
    static func makeAgentsTool(
        recordingIn calls: AgentsToolCalls, mountsWithNoGrant: Bool = false
    ) -> ToolResolver.AgentsToolFactory {
        { grant in
            await calls.record(grant)
            return grant != nil || mountsWithNoGrant ? ProbeTool(name: agentsName) : nil
        }
    }

    /// Resolves the entries against `makeCatalog()`.
    ///
    /// - Parameters:
    ///   - tools: The `tools` entries, or `nil` for no `tools` key.
    ///   - disallowed: The `disallowedTools` entries.
    ///   - agentsTool: The `agents` tool factory, or `nil`.
    /// - Returns: The tools and the diagnostics.
    static func resolve(
        _ tools: [String]?,
        disallowed: [String] = [],
        agentsTool: ToolResolver.AgentsToolFactory? = nil
    ) async throws -> (tools: [any Tool], diagnostics: [AgentDiagnostic]) {
        try await resolver.resolve(
            tools: tools?.map(ToolSpec.parse),
            disallowed: disallowed.map(ToolSpec.parse),
            catalog: makeCatalog(),
            agentsTool: agentsTool)
    }

    @Test("the catalog gives its names in sorted order")
    func catalogGivesSortedNames() {
        #expect(Self.makeCatalog().names == Self.catalogNames)
    }

    @Test("no tools key gives each catalog tool")
    func noToolsKeyGivesFullCatalog() async throws {
        let resolved = try await Self.resolve(nil)

        #expect(resolved.tools.map(\.name) == Self.catalogNames)
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("tools: Read gives only Read")
    func toolsReadGivesOnlyRead() async throws {
        let resolved = try await Self.resolve([Self.read])

        #expect(resolved.tools.map(\.name) == [Self.read])
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("disallowedTools: Read with no tools key removes Read from the full catalog")
    func disallowedReadRemovesReadFromFullCatalog() async throws {
        let resolved = try await Self.resolve(nil, disallowed: [Self.read])

        #expect(resolved.tools.map(\.name) == Self.catalogNames.filter { $0 != Self.read })
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("disallowedTools applies before tools")
    func disallowedAppliesBeforeTools() async throws {
        let resolved = try await Self.resolve([Self.read, Self.grep], disallowed: [Self.read])

        #expect(resolved.tools.map(\.name) == [Self.grep])
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("an MCP pattern in tools matches the names of its form", arguments: patternRows)
    func mcpPatternInToolsMatches(row: PatternRow) async throws {
        let resolved = try await Self.resolve([row.entry])

        #expect(resolved.tools.map(\.name) == row.expected)
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("an MCP pattern in disallowedTools removes the names of its form", arguments: patternRows)
    func mcpPatternInDisallowedRemoves(row: PatternRow) async throws {
        let resolved = try await Self.resolve(nil, disallowed: [row.entry])

        #expect(resolved.tools.map(\.name) == Self.catalogNames.filter { !row.expected.contains($0) })
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("an unknown name in tools is a warning and is skipped")
    func unknownToolIsWarnedAndSkipped() async throws {
        let resolved = try await Self.resolve([Self.read, Self.unknown])
        let diagnostic = try #require(resolved.diagnostics.first)

        #expect(resolved.tools.map(\.name) == [Self.read])
        #expect(resolved.diagnostics.count == 1)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.agent == Self.agentID)
        #expect(diagnostic.provenance == AgentDefinitionAttempt.inlineProvenance)
        #expect(diagnostic.message.contains("'tools'"))
        #expect(diagnostic.message.contains(Self.unknown))
    }

    @Test("an MCP pattern that matches no tool is a warning")
    func unmatchedPatternIsWarned() async throws {
        let entry = "mcp__none__*"
        let resolved = try await Self.resolve([entry])
        let diagnostic = try #require(resolved.diagnostics.first)

        #expect(resolved.tools.isEmpty)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.message.contains("mcp__none"))
    }

    @Test("an unknown name in disallowedTools is a warning, and it is first")
    func unknownDisallowedIsWarnedFirst() async throws {
        let resolved = try await Self.resolve([Self.unknown], disallowed: [Self.unknown])

        #expect(resolved.diagnostics.map(\.severity) == [.warning, .warning])
        #expect(resolved.diagnostics.first?.message.contains("'disallowedTools'") == true)
        #expect(resolved.diagnostics.last?.message.contains("'tools'") == true)
    }

    @Test("a denied name in tools is removed with no warning")
    func deniedToolIsRemovedSilently() async throws {
        let resolved = try await Self.resolve([Self.read], disallowed: [Self.read])

        #expect(resolved.tools.isEmpty)
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("two resolves give two different tool instances")
    func twoResolvesGiveNewInstances() async throws {
        let first = try await Self.resolve([Self.read])
        let second = try await Self.resolve([Self.read])
        let firstTool = try #require(first.tools.first as? ProbeTool)
        let secondTool = try #require(second.tools.first as? ProbeTool)

        #expect(firstTool !== secondTool)
    }

    @Test("Agent(a, b) calls the agents tool factory with [a, b]")
    func agentWithNamesLimitsTheNames() async throws {
        let calls = AgentsToolCalls()
        let entry = "Agent(\(Self.firstAgent), \(Self.secondAgent))"
        let resolved = try await Self.resolve([entry], agentsTool: Self.makeAgentsTool(recordingIn: calls))

        #expect(resolved.tools.map(\.name) == [Self.agentsName])
        #expect(await calls.grants == [.only([Self.firstAgent, Self.secondAgent])])
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("Agent, and the name agents, give the agents tool with all names", arguments: ["Agent", agentsName])
    func agentAloneAllowsAllNames(entry: String) async throws {
        let calls = AgentsToolCalls()
        let resolved = try await Self.resolve([entry], agentsTool: Self.makeAgentsTool(recordingIn: calls))

        #expect(resolved.tools.map(\.name) == [Self.agentsName])
        #expect(await calls.grants == [.all])
    }

    @Test("two Agent(...) entries give the union of their names")
    func agentEntriesMerge() async throws {
        let calls = AgentsToolCalls()
        let entries = ["Agent(\(Self.firstAgent))", "Agent(\(Self.secondAgent), \(Self.firstAgent))"]
        _ = try await Self.resolve(entries, agentsTool: Self.makeAgentsTool(recordingIn: calls))

        #expect(await calls.grants == [.only([Self.firstAgent, Self.secondAgent])])
    }

    @Test("Agent with Agent(a) gives all names")
    func agentAloneWinsOverNames() async throws {
        let calls = AgentsToolCalls()
        _ = try await Self.resolve(
            ["Agent(\(Self.firstAgent))", "Agent"], agentsTool: Self.makeAgentsTool(recordingIn: calls))

        #expect(await calls.grants == [.all])
    }

    @Test("no tools key asks the factory with no grant, and a factory that gives no tool adds no agents tool")
    func noToolsKeyGivesNoAgentsTool() async throws {
        let calls = AgentsToolCalls()
        let resolved = try await Self.resolve(nil, agentsTool: Self.makeAgentsTool(recordingIn: calls))

        #expect(resolved.tools.map(\.name) == Self.catalogNames)
        #expect(await calls.grants == [nil])
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("no tools key mounts the tool that the factory gives with no grant")
    func noToolsKeyMountsTheToolOfNoGrant() async throws {
        let calls = AgentsToolCalls()
        let resolved = try await Self.resolve(
            nil, agentsTool: Self.makeAgentsTool(recordingIn: calls, mountsWithNoGrant: true))

        #expect(resolved.tools.map(\.name) == Self.catalogNames + [Self.agentsName])
        #expect(await calls.grants == [nil])
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("a tools key with no Agent entry mounts the tool that the factory gives with no grant")
    func toolsKeyWithNoAgentEntryMountsTheToolOfNoGrant() async throws {
        let calls = AgentsToolCalls()
        let resolved = try await Self.resolve(
            [Self.read], agentsTool: Self.makeAgentsTool(recordingIn: calls, mountsWithNoGrant: true))

        #expect(resolved.tools.map(\.name) == [Self.read, Self.agentsName])
        #expect(await calls.grants == [nil])
    }

    @Test("Agent in disallowedTools gives no tool, also when the factory gives a tool with no grant",
          arguments: ["Agent", agentsName, "Agent(\(firstAgent))"])
    func disallowedAgentDeniesTheToolOfNoGrant(entry: String) async throws {
        let calls = AgentsToolCalls()
        let resolved = try await Self.resolve(
            nil, disallowed: [entry], agentsTool: Self.makeAgentsTool(recordingIn: calls, mountsWithNoGrant: true))

        #expect(resolved.tools.map(\.name) == Self.catalogNames)
        #expect(await calls.grants.isEmpty)
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("no tools key does not give a catalog tool with the name agents when an agents tool factory is present")
    func noToolsKeyGivesNoCatalogAgentsTool() async throws {
        var catalog = Self.makeCatalog()
        catalog.register(Self.agentsName) { ProbeTool(name: Self.agentsName) }
        let calls = AgentsToolCalls()
        let resolved = try await Self.resolver.resolve(
            tools: nil, disallowed: [], catalog: catalog, agentsTool: Self.makeAgentsTool(recordingIn: calls))

        #expect(resolved.tools.map(\.name) == Self.catalogNames)
        #expect(await calls.grants == [nil])
    }

    @Test("Agent in disallowedTools removes the agents tool", arguments: ["Agent", agentsName, "Agent(\(firstAgent))"])
    func disallowedAgentRemovesAgentsTool(entry: String) async throws {
        let calls = AgentsToolCalls()
        let resolved = try await Self.resolve(
            [Self.read, "Agent"], disallowed: [entry], agentsTool: Self.makeAgentsTool(recordingIn: calls))

        #expect(resolved.tools.map(\.name) == [Self.read])
        #expect(await calls.grants.isEmpty)
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("with no agents tool factory, Agent is an unknown name")
    func agentWithNoFactoryIsUnknown() async throws {
        let resolved = try await Self.resolve(["Agent(\(Self.firstAgent))"])
        let diagnostic = try #require(resolved.diagnostics.first)

        #expect(resolved.tools.isEmpty)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.message.contains("Agent(\(Self.firstAgent))"))
    }

    @Test("the unknown-disallowed-tool fixture gives one warning, first")
    func unknownDisallowedFixtureIsWarnedFirst() throws {
        let attempt = AgentDefinitionAttempt.broken("unknown-disallowed-tool")
        let definition = try #require(attempt.definition)
        let diagnostics = ToolResolver.diagnostics(
            of: definition, catalog: Self.makeCatalog(), hasAgentsTool: true, atMaxDepth: false)
        let diagnostic = try #require(diagnostics.first)

        #expect(diagnostics.count == 1)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.agent == definition.id)
        #expect(diagnostic.provenance == definition.provenance)
        #expect(diagnostic.message.contains("'disallowedTools'"))
        #expect(diagnostic.message.contains(Self.unknown))
    }

    @Test(
        "an incorrect tools or disallowedTools value resolves to less access",
        arguments: [
            ("tools: 3", [String]()),
            ("tools: [Read, 3]", [read]),
            ("disallowedTools: {Bash: true}", []),
            ("disallowedTools: [Grep, 3]", [])
        ])
    func incorrectToolKeyResolvesToLessAccess(yaml: String, expected: [String]) async throws {
        let definition = try #require(
            AgentDefinitionAttempt.inline("\(AgentDefinitionAttempt.validDescription)\n\(yaml)").definition)
        let calls = AgentsToolCalls()
        let resolved = try await Self.resolver.resolve(
            tools: definition.tools?.map(ToolSpec.parse),
            disallowed: definition.disallowedTools.map(ToolSpec.parse),
            catalog: Self.makeCatalog(),
            agentsTool: Self.makeAgentsTool(recordingIn: calls))

        #expect(resolved.tools.map(\.name) == expected)
        #expect(await calls.grants == [nil])
    }

    @Test("the warnings of a definition put the disallowedTools warnings first")
    func definitionWarningsPutDisallowedFirst() throws {
        let yaml = """
            \(AgentDefinitionAttempt.validDescription)
            tools: Read, OtherMissingTool
            disallowedTools: \(Self.unknown)
            """
        let definition = try #require(AgentDefinitionAttempt.inline(yaml).definition)
        let diagnostics = ToolResolver.diagnostics(
            of: definition, catalog: Self.makeCatalog(), hasAgentsTool: false, atMaxDepth: false)

        #expect(diagnostics.map(\.severity) == [.warning, .warning])
        #expect(diagnostics.first?.message.contains(Self.unknown) == true)
        #expect(diagnostics.last?.message.contains("OtherMissingTool") == true)
    }

    @Test("at maxDepth, an Agent entry gives one warning for a run with a caller and for a host-started run",
          arguments: ["Agent", agentsName, "Agent(\(firstAgent))"])
    func agentEntryAtMaxDepthIsWarned(entry: String) throws {
        let definition = try #require(
            AgentDefinitionAttempt.inline("\(AgentDefinitionAttempt.validDescription)\ntools: \(entry)").definition)
        let diagnostics = ToolResolver.diagnostics(
            of: definition, catalog: Self.makeCatalog(), hasAgentsTool: true, atMaxDepth: true)
        let diagnostic = try #require(diagnostics.first)

        #expect(diagnostics.count == 1)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.agent == definition.id)
        #expect(diagnostic.message.contains(Self.callerRunMaxDepthPhrase))
        #expect(diagnostic.message.contains(Self.hostStartedMaxDepthPhrase))
    }

    @Test("below maxDepth, an Agent entry gives no warning")
    func agentEntryBelowMaxDepthIsNotWarned() throws {
        let definition = try #require(
            AgentDefinitionAttempt.inline("\(AgentDefinitionAttempt.validDescription)\ntools: Agent").definition)

        let diagnostics = ToolResolver.diagnostics(
            of: definition, catalog: Self.makeCatalog(), hasAgentsTool: true, atMaxDepth: false)

        #expect(diagnostics.isEmpty)
    }

    @Test("at maxDepth, an Agent entry that disallowedTools denies gives no maxDepth warning")
    func deniedAgentEntryAtMaxDepthIsNotWarned() throws {
        let yaml = "\(AgentDefinitionAttempt.validDescription)\ntools: Agent\ndisallowedTools: Agent"
        let definition = try #require(AgentDefinitionAttempt.inline(yaml).definition)

        let diagnostics = ToolResolver.diagnostics(
            of: definition, catalog: Self.makeCatalog(), hasAgentsTool: true, atMaxDepth: true)

        #expect(diagnostics.isEmpty)
    }
}
