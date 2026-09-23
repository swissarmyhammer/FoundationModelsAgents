import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Marketplace
import Testing

/// Pins the local part of layer 2 (plan.md §4.1, §4.3 step 1, §12) on
/// `AgentRegistry` and `AgentCatalog`.
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

    /// The path of an agent file in a child folder of `agents/`.
    private static let nestedAgentPath = "agents/nested/deep-agent.md"

    /// The id of the agent in `validAgentText`.
    private static let validAgentID = "deep-agent"

    /// The path of the file of `validAgentID` directly in `agents/`.
    private static let topLevelAgentPath = "agents/\(validAgentID).md"

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

    @Test("the fixture stack gives the local ids, and each file name is the id")
    func fixtureStackGivesTheLocalIDs() async throws {
        let catalog = try await AgentRegistry(stack: FixtureLibrary.stack()).loadedCatalog()

        #expect(catalog.definitions.map(\.id) == FixtureLibrary.localAgentIDs.sorted())
        #expect(catalog.definitions.allSatisfy { $0.url.lastPathComponent == "\($0.id).md" })
        #expect(catalog.listing.map(\.id) == catalog.definitions.map(\.id))
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
        #expect(definition.url == projectLayer.root.appendingPathComponent("agents/\(Self.sharedAgent).md"))
    }

    @Test("the user code-reviewer.md wins over the defaults copy, with one advisory")
    func userCopyWinsWithOneAdvisory() async throws {
        let layers = Array(FixtureLibrary.stack().layers.prefix(Self.layersBelowProject))
        let catalog = try await AgentRegistry(layers: layers).loadedCatalog()
        let definition = try #require(catalog.definition(named: Self.sharedAgent))
        let hiddenURL = layers[Self.defaultsLayerIndex].root.appendingPathComponent("agents/\(Self.sharedAgent).md")
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

    @Test("a .md file in a child folder of agents/ is not read")
    func childFolderFileIsNotRead() async throws {
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
        let diagnostics = catalog.diagnostics.filter { $0.provenance.url.lastPathComponent == "\(row.id).md" }

        #expect(diagnostics.map(\.severity) == row.severities)
        #expect((catalog.definition(named: row.id) != nil) == row.loads)
    }

    @Test("the good files next to the broken files load")
    func goodFilesNextToBrokenFilesLoad() async throws {
        let loaded = AgentDefinitionRows.broken.filter(\.loads).map(\.id).sorted()
        let catalog = try await Self.brokenCatalog()

        #expect(catalog.definitions.map(\.id) == loaded)
    }

    @Test("a frontmatter that does not decode gives an advisory, then a skip")
    func undecodedFrontmatterGivesAnAdvisoryThenASkip() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try layer.write(Self.listFrontmatterText, at: "agents/\(Self.listFrontmatterID).md")

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

        try layer.write(Self.validAgentText, at: Self.topLevelAgentPath)

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
