import Foundation
import FoundationModels
@testable import FoundationModelsAgents
import Testing

/// Pins ``ToolCatalog/registerKept(_:vocabulary:_:)``: each run gets the kept
/// tool, its factory gets the definition of the run, and the names of the
/// tool and of its capabilities are known names for the `tools` and
/// `disallowedTools` keys.
///
/// A host uses a kept tool for `runCode`: the tool filters its own
/// capabilities (`web`, `shell`, `mcp__<server>__<tool>`) with the keys of
/// the agent, thus a run gets the same filter as the root session.
@Suite("Kept tools")
struct KeptToolTests {
    /// The name of the kept tool.
    private static let keptName = "runCode"

    /// A capability of the kept tool.
    private static let web = "web"

    /// A second capability of the kept tool.
    private static let shell = "shell"

    /// An MCP capability of the kept tool, of a server that the catalog does
    /// not hold.
    private static let mcpCapability = "mcp__github__issues"

    /// The capability names of the kept tool.
    private static let vocabulary = [web, shell, mcpCapability]

    /// Gives the catalog of the resolver tests with the kept tool.
    ///
    /// - Parameter calls: The record of the agent id of each factory call.
    /// - Returns: The catalog.
    private static func catalog(recordingIn calls: CallRecord<String>) -> ToolCatalog {
        var catalog = ToolResolverTests.makeCatalog()
        catalog.registerKept(keptName, vocabulary: { vocabulary }) { definition in
            calls.add(definition.id)
            return ProbeTool(name: keptName)
        }
        return catalog
    }

    /// Resolves the entries over the catalog with the kept tool.
    ///
    /// - Parameters:
    ///   - tools: The `tools` entries, or `nil` for no `tools` key.
    ///   - disallowed: The `disallowedTools` entries.
    ///   - calls: The record of the factory calls.
    /// - Returns: The tools and the diagnostics.
    private static func resolve(
        _ tools: [String]?, disallowed: [String] = [], calls: CallRecord<String> = CallRecord()
    ) async throws -> (tools: [any Tool], diagnostics: [AgentDiagnostic]) {
        try await ToolResolverTests.resolve(tools, disallowed: disallowed, catalog: catalog(recordingIn: calls))
    }

    // MARK: - The resolution

    @Test("the catalog gives the kept names apart from its plain names")
    func theCatalogGivesTheKeptNames() {
        let catalog = Self.catalog(recordingIn: CallRecord())

        #expect(catalog.keptNames == [Self.keptName])
        #expect(catalog.names == ToolResolverTests.catalogNames)
    }

    @Test("no tools key gives the catalog tools, then the kept tool, and the factory gets the definition one time")
    func noToolsKeyGivesTheKeptTool() async throws {
        let calls = CallRecord<String>()

        let resolved = try await Self.resolve(nil, calls: calls)

        #expect(resolved.tools.map(\.name) == ToolResolverTests.catalogNames + [Self.keptName])
        #expect(calls.all == [ToolResolverTests.agentID])
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("a tools entry of a capability name keeps the kept tool and gives no warning",
          arguments: [[web], [web, shell], [keptName], ["mcp__github"], ["mcp__github__*"], ["mcp__*"]])
    func aCapabilityEntryGivesNoWarning(entries: [String]) async throws {
        let resolved = try await Self.resolve(entries)

        #expect(resolved.tools.map(\.name).contains(Self.keptName))
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("a tools entry of a capability name makes no plain tool")
    func aCapabilityEntryMakesNoPlainTool() async throws {
        let resolved = try await Self.resolve([Self.web, ToolResolverTests.read])

        #expect(resolved.tools.map(\.name) == [ToolResolverTests.read, Self.keptName])
    }

    @Test("disallowedTools does not remove the kept tool, and a capability name gives no warning",
          arguments: [[shell], [keptName], [web, shell], ["mcp__github"]])
    func disallowedToolsDoesNotRemoveTheKeptTool(entries: [String]) async throws {
        let resolved = try await Self.resolve(nil, disallowed: entries)

        #expect(resolved.tools.map(\.name).contains(Self.keptName))
        #expect(resolved.diagnostics.isEmpty)
    }

    @Test("a name that is in no vocabulary is still a warning")
    func anUnknownNameIsStillAWarning() async throws {
        let resolved = try await Self.resolve([ToolResolverTests.unknown])

        #expect(resolved.tools.map(\.name) == [Self.keptName])
        #expect(resolved.diagnostics.map(\.code) == [.unknownTool])
    }

    @Test("with no kept tool, a capability name is a warning")
    func aCapabilityNameWithNoKeptToolIsAWarning() async throws {
        let resolved = try await ToolResolverTests.resolve([Self.web])

        #expect(resolved.diagnostics.map(\.code) == [.unknownTool])
    }

    // MARK: - A run

    @Test("a new run gets the kept tool, made from its definition, and the template context gets the kept name")
    func aNewRunGetsTheKeptTool() async throws {
        let calls = CallRecord<String>()
        let names = CallRecord<[String]>()
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([]), tools: Self.catalog(recordingIn: calls))
        defer { try? harness.delete() }
        let environment = harness.environment(
            maxRetainedRuns: AgentEnvironment.defaultMaxRetainedRuns,
            runTemplateContext: { _, toolNames in
                names.add(toolNames)
                return [:]
            })

        let setup = try await AgentSessionMaker(
            environment: environment, renderer: AgentBodyRenderer(registry: harness.registry)
        ).resolveSetup(for: harness.request(AgentRunTests.testWriter, prompt: "kept-key"), family: ParentRun.Family())

        #expect(setup.tools.map(\.name).contains(Self.keptName))
        #expect(calls.all == [AgentRunTests.testWriter])
        #expect(names.all.count == 1)
        #expect(names.all.allSatisfy { $0.contains(Self.keptName) })
    }

    @Test("a restored run gets the kept tool, made from its definition")
    func aRestoredRunGetsTheKeptTool() async throws {
        let calls = CallRecord<String>()
        let setup = try await RestoredRunFixture.make(deferStart: true, tools: Self.catalog(recordingIn: calls))
        defer { try? setup.harness.delete() }
        await setup.runner.stop()

        #expect(calls.all == [AgentRunTests.testWriter, AgentRunTests.testWriter])
    }

    @Test("runner.catalog() gives no warning for a capability entry")
    func theRunnerCatalogGivesNoWarningForACapabilityEntry() async throws {
        let layer = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: AgentFolderFixture.helperID): """
                ---
                name: \(AgentFolderFixture.helperID)
                description: \(AgentFolderFixture.description)
                tools: [\(Self.web), \(ToolResolverTests.read)]
                disallowedTools: [\(Self.shell)]
                ---
                \(AgentFolderFixture.body)
                """
        ])
        defer { try? layer.delete() }
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([]), registry: AgentRegistry(layers: [layer.layer]),
            tools: Self.catalog(recordingIn: CallRecord()))
        defer { try? harness.delete() }

        let diagnostics = harness.makeRunner().catalog().diagnostics

        #expect(!diagnostics.contains { $0.code == .unknownTool })
    }
}
