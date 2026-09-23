import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Marketplace
import Testing

/// Pins the reload part of layer 2 (plan.md §4.1, §10) on `AgentRegistry`.
///
/// Each row works on a `TemporaryLayer`. A watch row uses the real
/// `DotfolderWatcher`, thus it waits on `onReload` for the catalog that it
/// expects. The time limit stops a row that never gets that catalog.
@Suite("Agent registry reload")
struct AgentRegistryReloadTests {
    /// The id of the agent that a row adds, changes, or removes.
    private static let agentID = "live-agent"

    /// The path of the file of `agentID`, relative to a layer root.
    private static let agentPath = "agents/\(agentID).md"

    /// The description of the first version of the agent file.
    private static let firstDescription = "The first version."

    /// The description of the changed version of the agent file.
    private static let changedDescription = "The changed version."

    /// The count of the writes of one burst.
    private static let burstWriteCount = 5

    /// The ids of the agents that a burst adds, one for each write.
    private static let burstAgentIDs = (Int.zero..<burstWriteCount).map { "burst-agent-\($0)" }

    /// The count of the `layerUpdates` streams that one registry takes.
    private static let subscriptionsOfOneRegistry = 1

    /// The marketplace provenance of the layer of `SignalingMarketplaceProvider`.
    private static let provenance = MarketplaceProvenance(id: "signal-market", url: "file:///signal-market")

    @Test("load() publishes its catalog on onReload")
    func loadPublishesItsCatalog() async throws {
        let layer = try Self.layerWithAgent()
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer])
        let reloads = registry.onReload

        try await registry.load()

        let published = try #require(await reloads.first { _ in true })
        #expect(published.definitions.map(\.id) == [Self.agentID])
    }

    @Test("reload() publishes the new catalog on onReload")
    func reloadPublishesTheNewCatalog() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer])
        try await registry.load()
        let reloads = registry.onReload

        try layer.write(Self.agentText(description: Self.firstDescription), at: Self.agentPath)
        try await registry.reload()

        let published = try #require(await reloads.first { _ in true })
        #expect(published.definitions.map(\.id) == [Self.agentID])
    }

    @Test("two readers of onReload each get the catalog")
    func twoReadersEachGetTheCatalog() async throws {
        let layer = try Self.layerWithAgent()
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer])
        let first = registry.onReload
        let second = registry.onReload

        try await registry.load()

        #expect(try #require(await first.first { _ in true }).definitions.map(\.id) == [Self.agentID])
        #expect(try #require(await second.first { _ in true }).definitions.map(\.id) == [Self.agentID])
    }

    @Test("init takes no layerUpdates stream, and load() and reload() take one together")
    func loadTakesTheLayerUpdatesStreamOneTime() async throws {
        let market = try TemporaryLayer.makeEmpty()
        defer { try? market.delete() }
        let provider = SignalingMarketplaceProvider(layers: [Self.marketplaceLayer(at: market.root)])

        let registry = AgentRegistry(marketplaces: provider, stack: DotfolderStack(layers: []))

        #expect(provider.subscriptionCount == .zero)
        try await registry.load()
        try await registry.reload()
        #expect(provider.subscriptionCount == Self.subscriptionsOfOneRegistry)
    }

    @Test("a layerUpdates value gives a new catalog on onReload", .timeLimit(.minutes(1)))
    func layerUpdateGivesANewCatalog() async throws {
        let market = try TemporaryLayer.makeEmpty()
        defer { try? market.delete() }
        let provider = SignalingMarketplaceProvider(layers: [Self.marketplaceLayer(at: market.root)])
        let registry = AgentRegistry(marketplaces: provider, stack: DotfolderStack(layers: []))
        try await registry.load()
        let reloads = registry.onReload

        try market.write(Self.agentText(description: Self.firstDescription), at: Self.agentPath)
        provider.signal()

        let published = try #require(await reloads.first { _ in true })
        let definition = try #require(published.definition(named: Self.agentID))
        #expect(definition.marketplace == Self.provenance)
        #expect(registry.catalog().definition(named: Self.agentID) != nil)
    }

    @Test("the add of a watched file gives a new catalog", .timeLimit(.minutes(1)))
    func addOfAWatchedFileGivesANewCatalog() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer], watch: true)
        try await registry.load()
        let reloads = registry.onReload

        try layer.write(Self.agentText(description: Self.firstDescription), at: Self.agentPath)

        let published = try #require(await reloads.first { $0.definition(named: Self.agentID) != nil })
        #expect(published.definitions.map(\.id) == [Self.agentID])
    }

    @Test("the change of a watched file gives a new catalog", .timeLimit(.minutes(1)))
    func changeOfAWatchedFileGivesANewCatalog() async throws {
        let layer = try Self.layerWithAgent()
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer], watch: true)
        try await registry.load()
        let reloads = registry.onReload

        try layer.write(Self.agentText(description: Self.changedDescription), at: Self.agentPath)

        let published = try #require(
            await reloads.first { Self.description(in: $0) == Self.changedDescription })
        #expect(published.definitions.map(\.id) == [Self.agentID])
    }

    @Test("the remove of a watched file gives a new catalog", .timeLimit(.minutes(1)))
    func removeOfAWatchedFileGivesANewCatalog() async throws {
        let layer = try Self.layerWithAgent()
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer], watch: true)
        try await registry.load()
        let reloads = registry.onReload

        try layer.remove(Self.agentPath)

        let published = try #require(await reloads.first { _ in true })
        #expect(published.definitions.isEmpty)
        #expect(registry.catalog().definitions.isEmpty)
    }

    @Test("a burst of writes gives one final catalog with the last state", .timeLimit(.minutes(1)))
    func burstOfWritesGivesOneFinalCatalog() async throws {
        let layer = try Self.layerWithAgent()
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer], watch: true)
        try await registry.load()
        let reloads = registry.onReload

        for id in Self.burstAgentIDs {
            try layer.write(Self.agentText(description: id), at: Self.agentPath)
            try layer.write(Self.agentText(named: id, description: id), at: "agents/\(id).md")
        }

        let published = try #require(await reloads.first { _ in true })
        let lastID = try #require(Self.burstAgentIDs.last)
        #expect(published.definitions.map(\.id) == ([Self.agentID] + Self.burstAgentIDs).sorted())
        #expect(Self.description(in: published) == lastID)
        #expect(Self.description(in: registry.catalog()) == lastID)
    }

    @Test("the release of the registry finishes onReload", .timeLimit(.minutes(1)))
    func releaseOfTheRegistryFinishesOnReload() async throws {
        let layer = try Self.layerWithAgent()
        defer { try? layer.delete() }

        let reloads = try await Self.onReloadOfAReleasedRegistry(over: layer)

        var iterator = reloads.makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }

    /// Makes a watching registry over `layer`, loads it, and releases it.
    ///
    /// - Parameter layer: The layer of the registry.
    /// - Returns: The `onReload` stream that the registry gave after its
    ///   load.
    /// - Throws: The error of `load()`.
    private static func onReloadOfAReleasedRegistry(
        over layer: TemporaryLayer
    ) async throws -> AsyncStream<AgentCatalog> {
        let registry = AgentRegistry(layers: [layer.layer], watch: true)
        try await registry.load()
        return registry.onReload
    }

    /// Makes a layer that holds the first version of the agent file.
    ///
    /// - Returns: The new layer.
    /// - Throws: The error of the file system.
    private static func layerWithAgent() throws -> TemporaryLayer {
        let layer = try TemporaryLayer.makeEmpty()
        try layer.write(agentText(description: firstDescription), at: agentPath)
        return layer
    }

    /// A marketplace layer over `root` with the provenance of the rows.
    ///
    /// - Parameter root: The root of the layer.
    /// - Returns: The layer. A watcher does not watch it.
    private static func marketplaceLayer(at root: URL) -> MarketplaceLayer {
        MarketplaceLayer(layer: DotfolderStack.Layer(source: .marketplace, root: root), provenance: provenance)
    }

    /// The description of the agent `agentID` in `catalog`.
    ///
    /// - Parameter catalog: The catalog.
    /// - Returns: The description, or `nil` when the catalog does not hold
    ///   the agent.
    private static func description(in catalog: AgentCatalog) -> String? {
        catalog.definition(named: agentID)?.description
    }

    /// A valid agent file.
    ///
    /// - Parameters:
    ///   - id: The name of the agent. The default is `agentID`.
    ///   - description: The description of the agent.
    /// - Returns: The text of the file.
    private static func agentText(named id: String = agentID, description: String) -> String {
        """
        ---
        name: \(id)
        description: \(description)
        ---

        You are an agent of a test.
        """
    }
}
