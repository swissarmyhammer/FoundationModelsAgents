import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Marketplace
import MarketplaceFixtures
import Testing

/// Pins the marketplace part of layer 2 (plan.md §4.1, §6.1, §16) on
/// `AgentRegistry`.
///
/// The marketplace layers are below the local layers. Each marketplace
/// definition keeps its `MarketplaceProvenance` and its marketplace layer.
@Suite("Agent registry marketplace")
struct AgentRegistryMarketplaceTests {
    /// The position of the one marketplace layer in the layers of a
    /// registry.
    private static let marketplaceLayerIndex = 0

    /// The position of the project layer above one marketplace layer.
    private static let projectLayerIndex = 1

    /// The agent that the fixture marketplace and the project override both
    /// hold.
    private static let sharedAgent = "security-reviewer"

    /// The folder that the `path:` field of a `file://` source names.
    private static let libraryFolderName = "library"

    /// The agent of the `file://` folder.
    private static let libraryAgent = "library-agent"

    /// The count of marketplace layers of a store with one source.
    private static let oneSourceLayerCount = 1

    /// The agent in the plugin shape under the `file://` folder.
    private static let pluginAgent = "plugin-agent"

    /// The path of the file of `pluginAgent`, relative to the `file://`
    /// folder. A snapshot moves such a file to `agents/`; a `file://` source
    /// does not.
    private static let pluginAgentPath = "plugins/extra-tools/agents/\(pluginAgent).md"

    /// The path of the skill file of a marketplace with no `agents/` folder.
    private static let skillPath = "review/SKILL.md"

    /// The body of each agent file that a test writes.
    private static let agentBody = "You are an agent of a test."

    /// A skill file of a marketplace with no `agents/` folder.
    private static let skillText = """
        ---
        name: review
        description: Reviews code.
        ---

        Review the code.
        """

    @Test("the fixture provider gives its agents, each with its provenance and its marketplace layer")
    func fixtureProviderGivesItsAgentsWithProvenance() async throws {
        let provider = try await FixtureMarketplaceProvider.make()
        defer { try? provider.delete() }
        let marketplace = try #require(provider.marketplaceLayers().first)

        let catalog = AgentRegistry(marketplaces: provider, stack: DotfolderStack(layers: [])).catalog()

        #expect(marketplace.provenance.id == FixtureMarketplaceProvider.marketplaceID)
        #expect(marketplace.provenance.sha == provider.sha)
        #expect(marketplace.provenance.catalogVersion == FixtureMarketplaceProvider.catalogVersion)
        #expect(catalog.definitions.map(\.id) == FixtureMarketplaceProvider.agentIDs)
        for definition in catalog.definitions {
            #expect(definition.marketplace == marketplace.provenance)
            #expect(definition.listing.provenance.marketplace == marketplace.provenance)
            #expect(definition.marketplaceLayer?.layer.root == marketplace.layer.root)
            #expect(definition.layer.source == .marketplace)
            #expect(definition.provenance.layerIndex == Self.marketplaceLayerIndex)
            #expect(definition.url == Self.agentURL(definition.id, inLayerRoot: marketplace.layer.root))
        }
    }

    @Test("the marketplace layers are below the local layers")
    func marketplaceLayersAreBelowTheLocalLayers() async throws {
        let provider = try await FixtureMarketplaceProvider.make()
        defer { try? provider.delete() }
        let project = try TemporaryLayer.makeEmpty()
        defer { try? project.delete() }
        let marketplace = try #require(provider.marketplaceLayers().first)

        let registry = AgentRegistry(marketplaces: provider, stack: DotfolderStack(layers: [project.layer]))

        #expect(registry.layers.map(\.root) == [marketplace.layer.root, project.root])
        #expect(registry.marketplaceLayers.map(\.provenance) == [marketplace.provenance])
        #expect(registry.localLayers.map(\.root) == [project.root])
    }

    @Test("a project agent with the same name wins over the marketplace agent, with an advisory")
    func projectAgentWinsOverTheMarketplaceAgent() async throws {
        let provider = try await FixtureMarketplaceProvider.make()
        defer { try? provider.delete() }
        let project = try TemporaryLayer.makeEmpty()
        defer { try? project.delete() }
        try project.write(Self.agentText(named: Self.sharedAgent), at: Self.agentPath(Self.sharedAgent))
        let marketplace = try #require(provider.marketplaceLayers().first)

        let catalog = AgentRegistry(marketplaces: provider, stack: DotfolderStack(layers: [project.layer])).catalog()

        let definition = try #require(catalog.definition(named: Self.sharedAgent))
        let expected = AgentDiagnostic(
            severity: .advisory, agent: Self.sharedAgent, provenance: definition.provenance,
            message: AgentCatalogBuilder.hiddenCopyMessage(
                url: Self.agentURL(Self.sharedAgent, inLayerRoot: marketplace.layer.root),
                layerIndex: Self.marketplaceLayerIndex))
        #expect(definition.layer.source == .project)
        #expect(definition.provenance.layerIndex == Self.projectLayerIndex)
        #expect(definition.marketplace == nil)
        #expect(definition.marketplaceLayer == nil)
        #expect(definition.body.contains(Self.agentBody))
        #expect(catalog.diagnostics.filter { $0.agent == Self.sharedAgent } == [expected])
    }

    @Test("a marketplace layer with no agents/ folder gives no agents and no error")
    func marketplaceLayerWithNoAgentsFolderGivesNoAgents() throws {
        let folder = try TemporaryLayer.makeEmpty()
        defer { try? folder.delete() }
        try folder.write(Self.skillText, at: Self.skillPath)
        let fixture = try MarketplaceStoreFixture(sources: [MarketplaceSource(Self.url(ofFolder: folder.root))])

        let registry = AgentRegistry(marketplaces: fixture.store, stack: DotfolderStack(layers: []))

        #expect(registry.marketplaceLayers.count == Self.oneSourceLayerCount)
        #expect(registry.catalog().definitions.isEmpty)
        #expect(registry.catalog().diagnostics.isEmpty)
    }

    @Test("a file:// source with path: gives its folder unchanged")
    func fileSourceWithPathGivesItsFolderUnchanged() throws {
        let folder = try TemporaryLayer.makeEmpty()
        defer { try? folder.delete() }
        let library = "\(Self.libraryFolderName)/"
        try folder.write(Self.agentText(named: Self.libraryAgent), at: library + Self.agentPath(Self.libraryAgent))
        try folder.write(Self.agentText(named: Self.pluginAgent), at: library + Self.pluginAgentPath)
        let fixture = try MarketplaceStoreFixture(
            sources: [MarketplaceSource(Self.url(ofFolder: folder.root), path: Self.libraryFolderName)])
        let libraryRoot = folder.root.appendingPathComponent(Self.libraryFolderName, isDirectory: true)

        let catalog = AgentRegistry(marketplaces: fixture.store, stack: DotfolderStack(layers: [])).catalog()

        let definition = try #require(catalog.definition(named: Self.libraryAgent))
        #expect(catalog.definitions.map(\.id) == [Self.libraryAgent])
        #expect(Self.canonicalPath(of: definition.layer.root) == Self.canonicalPath(of: libraryRoot))
        #expect(
            Self.canonicalPath(of: definition.url)
                == Self.canonicalPath(of: Self.agentURL(Self.libraryAgent, inLayerRoot: libraryRoot)))
        #expect(definition.marketplaceLayer?.isWatchable == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.cacheDirectory.path).isEmpty)
    }

    /// The path of the file of `id`, relative to a layer root.
    ///
    /// - Parameter id: The agent id.
    /// - Returns: `agents/<id>.md`.
    private static func agentPath(_ id: String) -> String {
        "\(MarketplaceLayer.agentsDirectoryName)/\(id).md"
    }

    /// The URL of the file of `id` in the layer at `root`.
    ///
    /// - Parameters:
    ///   - id: The agent id.
    ///   - root: The layer root.
    /// - Returns: `<root>/agents/<id>.md`.
    private static func agentURL(_ id: String, inLayerRoot root: URL) -> URL {
        root.appendingPathComponent(agentPath(id))
    }

    /// A valid agent file with the name `id`.
    ///
    /// - Parameter id: The agent id.
    /// - Returns: The text of the file.
    private static func agentText(named id: String) -> String {
        """
        ---
        name: \(id)
        description: An agent of a test.
        ---

        \(agentBody)
        """
    }

    /// The `file://` URL of a folder, with no `.git` suffix, thus a local
    /// folder source.
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The URL text.
    private static func url(ofFolder folder: URL) -> String {
        "file://\(folder.path)"
    }

    /// The path of `url` with each symbolic link resolved, thus
    /// `/var/folders` and `/private/var/folders` compare equal.
    ///
    /// - Parameter url: The URL.
    /// - Returns: The resolved path.
    private static func canonicalPath(of url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }
}
