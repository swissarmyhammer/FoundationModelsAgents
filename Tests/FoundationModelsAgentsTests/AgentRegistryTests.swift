import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Marketplace
import Testing

/// Pins the local part of layer 2 on `AgentRegistry` and `AgentCatalog`.
///
/// The fixture rows read `Examples/agent-library`. A row that must change
/// files, or that needs a file the fixture library does not hold, works on a
/// `TemporaryLayer`.
@Suite("Agent registry")
struct AgentRegistryTests {
    /// The position of the defaults layer in `FixtureLibrary.stack()`.
    private static let defaultsLayerIndex = 0

    /// The position of the user layer in `FixtureLibrary.stack()`.
    private static let userLayerIndex = 1

    /// The position of the project layer in `FixtureLibrary.stack()`.
    private static let projectLayerIndex = 2

    /// The count of layers below the project layer: defaults and user.
    private static let layersBelowProject = 2

    /// The agent that each local layer holds a copy of.
    private static let sharedAgent = "code-reviewer"

    /// The agent ids of the defaults layer.
    private static let defaultsAgentIDs = ["code-reviewer", "lead", "test-writer"]

    /// The path of a Markdown file in a child folder of `agents/` that holds
    /// no `AGENT.md`.
    private static let nestedAgentPath = "agents/nested/deep-agent.md"

    /// The id of the agent in `validAgentText`.
    private static let validAgentID = "deep-agent"

    /// The path of the document of `validAgentID`: its agent folder holds
    /// it.
    private static let validAgentPath = AgentDocumentPath.of(validAgentID)

    /// The path of an agent file of the old format, directly in `agents/`.
    private static let oldFormatAgentPath = "agents/\(validAgentID).md"

    /// The name of a resource file in the agent folder of `validAgentID`.
    private static let resourceName = "checklist.md"

    /// The path of the resource file in the agent folder of `validAgentID`.
    private static let resourcePath = "agents/\(validAgentID)/\(resourceName)"

    /// A valid agent file.
    private static let validAgentText = """
        ---
        name: \(validAgentID)
        description: A valid agent of a test.
        ---

        You are an agent of a test.
        """

    /// An agent file whose frontmatter is a list, not a mapping, thus the
    /// frontmatter does not decode.
    private static let listFrontmatterText = """
        ---
        - one
        - two
        ---

        The frontmatter is a list.
        """

    /// The id of the file that holds `listFrontmatterText`.
    private static let listFrontmatterID = "list-frontmatter"

    /// The id of the old-format fixture of `broken/agents/`.
    private static let oldFormatFixtureID = "old-format"

    /// The file name of the old-format fixture of `broken/agents/`.
    private static let oldFormatFixtureName = "\(oldFormatFixtureID).md"

    @Test("the fixture stack gives the local ids, and each folder name is the id")
    func fixtureStackGivesTheLocalIDs() async throws {
        let catalog = try await AgentRegistry(stack: FixtureLibrary.stack()).loadedCatalog()

        #expect(catalog.definitions.map(\.id) == FixtureLibrary.localAgentIDs.sorted())
        #expect(catalog.definitions.allSatisfy { $0.url.lastPathComponent == AgentDocumentPath.documentName })
        #expect(catalog.definitions.allSatisfy { $0.folderURL.lastPathComponent == $0.id })
        #expect(catalog.listing.map(\.id) == catalog.definitions.map(\.id))
    }

    @Test("agents/<name>/AGENT.md loads, and its id is the folder name")
    func agentFolderLoadsWithTheFolderNameAsTheID() async throws {
        let layer = try TemporaryLayer.make(holding: [Self.validAgentPath: Self.validAgentText])
        defer { try? layer.delete() }

        let catalog = try await AgentRegistry(layers: [layer.layer]).loadedCatalog()
        let definition = try #require(catalog.definition(named: Self.validAgentID))

        #expect(catalog.definitions.map(\.id) == [Self.validAgentID])
        #expect(catalog.diagnostics.isEmpty)
        #expect(definition.url == layer.root.appendingPathComponent(Self.validAgentPath))
    }

    @Test("the definition keeps the agent folder of the winning layer, which holds the resources")
    func definitionKeepsTheAgentFolder() async throws {
        let lower = try TemporaryLayer.make(holding: [Self.validAgentPath: Self.validAgentText])
        defer { try? lower.delete() }
        let higher = try TemporaryLayer.make(holding: [
            Self.validAgentPath: Self.validAgentText, Self.resourcePath: Self.validAgentText
        ])
        defer { try? higher.delete() }

        let catalog = try await AgentRegistry(layers: [lower.layer, higher.layer]).loadedCatalog()
        let definition = try #require(catalog.definition(named: Self.validAgentID))
        let resource = definition.folderURL.appendingPathComponent(Self.resourceName)

        #expect(definition.folderURL == higher.root.appendingPathComponent("agents/\(Self.validAgentID)"))
        #expect(FileManager.default.fileExists(atPath: resource.path))
    }

    @Test("an old agents/<id>.md file gives one warning and no agent")
    func oldFormatFileGivesOneWarning() async throws {
        let layer = try TemporaryLayer.make(holding: [Self.oldFormatAgentPath: Self.validAgentText])
        defer { try? layer.delete() }

        let catalog = try await AgentRegistry(layers: [layer.layer]).loadedCatalog()
        let diagnostic = try #require(catalog.diagnostics.first)

        #expect(catalog.definitions.isEmpty)
        #expect(catalog.diagnostics.count == 1)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.agent == Self.validAgentID)
        #expect(diagnostic.provenance.url == layer.root.appendingPathComponent(Self.oldFormatAgentPath))
        #expect(diagnostic.message.contains(Self.validAgentPath))
    }

    @Test("an old file next to the agent folder of the same id gives a warning, and the folder loads")
    func oldFormatFileNextToTheFolderGivesAWarning() async throws {
        let layer = try TemporaryLayer.make(holding: [
            Self.oldFormatAgentPath: Self.validAgentText, Self.validAgentPath: Self.validAgentText
        ])
        defer { try? layer.delete() }

        let catalog = try await AgentRegistry(layers: [layer.layer]).loadedCatalog()

        #expect(catalog.definitions.map(\.id) == [Self.validAgentID])
        #expect(catalog.diagnostics.map(\.severity) == [.warning])
    }

    @Test("each definition keeps its URL, its layer, and its layer index")
    func definitionKeepsItsProvenance() async throws {
        let stack = FixtureLibrary.stack()
        let catalog = try await AgentRegistry(stack: stack).loadedCatalog()
        let definition = try #require(catalog.definition(named: Self.sharedAgent))
        let projectLayer = stack.layers[Self.projectLayerIndex]

        #expect(definition.provenance.layerIndex == Self.projectLayerIndex)
        #expect(definition.layer.source == projectLayer.source)
        #expect(definition.layer.root == projectLayer.root)
        #expect(definition.provenance.layerRoot == projectLayer.root)
        #expect(definition.url == projectLayer.root.appendingPathComponent(AgentDocumentPath.of(Self.sharedAgent)))
    }

    @Test("the user code-reviewer folder wins over the defaults copy, with one advisory")
    func userCopyWinsWithOneAdvisory() async throws {
        let layers = Array(FixtureLibrary.stack().layers.prefix(Self.layersBelowProject))
        let catalog = try await AgentRegistry(layers: layers).loadedCatalog()
        let definition = try #require(catalog.definition(named: Self.sharedAgent))
        let hiddenURL = layers[Self.defaultsLayerIndex].root.appendingPathComponent(
            AgentDocumentPath.of(Self.sharedAgent))
        let expected = AgentDiagnostic(
            severity: .advisory, agent: Self.sharedAgent, provenance: definition.provenance,
            message: AgentCatalogBuilder.hiddenCopyMessage(url: hiddenURL, layerIndex: Self.defaultsLayerIndex))

        #expect(definition.provenance.layerIndex == Self.userLayerIndex)
        #expect(definition.layer.source == .user)
        #expect(catalog.diagnostics.filter { $0.agent == Self.sharedAgent } == [expected])
    }

    @Test("the project copy hides the user copy and the defaults copy, with one advisory each")
    func projectCopyHidesEachLowerCopy() async throws {
        let catalog = try await AgentRegistry(stack: FixtureLibrary.stack()).loadedCatalog()
        let advisories = catalog.diagnostics.filter { $0.agent == Self.sharedAgent && $0.severity == .advisory }

        #expect(advisories.count == Self.layersBelowProject)
        #expect(advisories.allSatisfy { $0.provenance.layerIndex == Self.projectLayerIndex })
    }

    @Test("a child folder of agents/ with no AGENT.md gives no agent and no diagnostic")
    func childFolderWithNoAgentDocumentIsNotAnAgent() async throws {
        let layer = try TemporaryLayer.copy(of: FixtureLibrary.defaultsDirectory)
        defer { try? layer.delete() }
        try layer.write(Self.validAgentText, at: Self.nestedAgentPath)

        let catalog = try await AgentRegistry(layers: [layer.layer]).loadedCatalog()

        #expect(catalog.definitions.map(\.id) == Self.defaultsAgentIDs)
        #expect(catalog.diagnostics.allSatisfy { !$0.provenance.url.path.contains("/nested/") })
    }

    @Test("a broken file gives its diagnostics", arguments: AgentDefinitionRows.broken)
    func brokenFileGivesItsDiagnostics(row: AgentDefinitionRows.BrokenRow) async throws {
        let catalog = try await Self.brokenCatalog()
        let diagnostics = catalog.diagnostics.filter { $0.provenance.url.path.hasSuffix(AgentDocumentPath.of(row.id)) }

        #expect(diagnostics.map(\.severity) == row.severities)
        #expect((catalog.definition(named: row.id) != nil) == row.loads)
    }

    @Test("the good files next to the broken files load")
    func goodFilesNextToBrokenFilesLoad() async throws {
        let loaded = AgentDefinitionRows.broken.filter(\.loads).map(\.id).sorted()
        let catalog = try await Self.brokenCatalog()

        #expect(catalog.definitions.map(\.id) == loaded)
    }

    @Test("the old-format fixture of broken/ gives one warning and no agent")
    func oldFormatFixtureGivesOneWarning() async throws {
        let catalog = try await Self.brokenCatalog()
        let warnings = catalog.diagnostics.filter { $0.provenance.url.lastPathComponent == Self.oldFormatFixtureName }

        #expect(warnings.map(\.severity) == [.warning])
        #expect(warnings.map(\.agent) == [Self.oldFormatFixtureID])
        #expect(catalog.definition(named: Self.oldFormatFixtureID) == nil)
    }

    @Test("a frontmatter that does not decode gives an advisory, then a skip")
    func undecodedFrontmatterGivesAnAdvisoryThenASkip() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try layer.write(Self.listFrontmatterText, at: AgentDocumentPath.of(Self.listFrontmatterID))

        let catalog = try await AgentRegistry(layers: [layer.layer]).loadedCatalog()

        #expect(catalog.definitions.isEmpty)
        #expect(catalog.diagnostics.map(\.severity) == [.advisory, .skip])
        #expect(catalog.diagnostics.allSatisfy { $0.agent == Self.listFrontmatterID })
    }

    @Test("no init reads a file: catalog() right after init is empty")
    func catalogIsEmptyBeforeLoad() {
        let registry = AgentRegistry(stack: FixtureLibrary.stack())

        #expect(registry.catalog().definitions.isEmpty)
        #expect(registry.catalog().diagnostics.isEmpty)
        #expect(registry.catalog().listing.isEmpty)
    }

    @Test("isLoaded is false after init, and true after the first load()")
    func isLoadedAfterTheFirstLoad() async throws {
        let registry = AgentRegistry(stack: FixtureLibrary.stack())
        #expect(!registry.isLoaded)

        try await registry.load()

        #expect(registry.isLoaded)
    }

    @Test("isLoaded is true after a reload() with no load() before it")
    func isLoadedAfterTheFirstReload() async throws {
        let registry = AgentRegistry(stack: FixtureLibrary.stack())

        try await registry.reload()

        #expect(registry.isLoaded)
    }

    @Test("after load(), catalog() holds the agents of the files")
    func loadFillsTheCatalog() async throws {
        let registry = AgentRegistry(layers: [FixtureLibrary.stack().layers[Self.defaultsLayerIndex]])

        try await registry.load()

        #expect(registry.catalog().definitions.map(\.id) == Self.defaultsAgentIDs)
    }

    @Test("catalog() gives the same catalog after the files are deleted, until reload()")
    func catalogDoesNoIOAfterTheBuild() async throws {
        let layer = try TemporaryLayer.copy(of: FixtureLibrary.defaultsDirectory)
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer])
        try await registry.load()
        let before = registry.catalog()

        try layer.remove(MarketplaceLayer.agentsDirectoryName)
        let after = registry.catalog()

        #expect(after.listing == before.listing)
        #expect(after.diagnostics == before.diagnostics)
        #expect(after.definitions.map(\.body) == before.definitions.map(\.body))
        #expect(before.definitions.map(\.id) == Self.defaultsAgentIDs)

        try await registry.reload()

        #expect(registry.catalog().definitions.isEmpty)
    }

    @Test("a file written after load() shows in catalog() only after reload()")
    func newFileShowsOnlyAfterReload() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer])
        try await registry.load()

        try layer.write(Self.validAgentText, at: Self.validAgentPath)

        #expect(registry.catalog().definitions.isEmpty)

        try await registry.reload()

        #expect(registry.catalog().definitions.map(\.id) == [Self.validAgentID])
    }

    @Test("a load() in a cancelled task throws, and the catalog stays empty")
    func cancelledLoadKeepsTheCatalog() async throws {
        let registry = AgentRegistry(stack: FixtureLibrary.stack())
        let load = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await registry.load()
        }

        await #expect(throws: CancellationError.self) { try await load.value }
        #expect(registry.catalog().definitions.isEmpty)
        #expect(!registry.isLoaded)
    }

    @Test("modelVisible holds only the model-visible definitions")
    func modelVisibleHoldsOnlyVisibleDefinitions() async throws {
        let catalog = try await AgentRegistry(stack: FixtureLibrary.stack()).loadedCatalog()

        #expect(catalog.modelVisible.map(\.id) == catalog.definitions.filter(\.isModelVisible).map(\.id))
        #expect(!catalog.modelVisible.contains { $0.id == "release-manager" })
    }

    @Test("the registry keeps its layers and its variables")
    func registryKeepsLayersAndVariables() {
        let stack = FixtureLibrary.stack()
        let variables = ["project": "acme"]
        let registry = AgentRegistry(stack: stack, variables: variables)

        #expect(registry.layers.map(\.root) == stack.layers.map(\.root))
        #expect(registry.variables == variables)
    }

    /// Builds the catalog of the `broken/` layer.
    ///
    /// - Returns: The catalog of a registry over the one layer whose
    ///   `agents/` folder is `broken/agents/`.
    /// - Throws: The error of `load()`.
    private static func brokenCatalog() async throws -> AgentCatalog {
        let layer = DotfolderStack.Layer(
            source: .project, root: FixtureLibrary.brokenAgentsDirectory.deletingLastPathComponent())
        return try await AgentRegistry(layers: [layer]).loadedCatalog()
    }
}
