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
    private static let agentPath = filePath(of: agentID)

    /// The description of the first version of the agent file.
    private static let firstDescription = "The first version."

    /// The description of the changed version of the agent file.
    private static let changedDescription = "The changed version."

    /// The count of the writes of one burst.
    private static let burstWriteCount = 5

    /// The ids of the agents that a burst adds, one for each write.
    private static let burstAgentIDs = (Int.zero..<burstWriteCount).map { "burst-agent-\($0)" }

    /// The id of the agent that marks the end of the read after a burst.
    private static let markerID = "marker-agent"

    /// The count of the writes of a split burst before its pause.
    private static let firstHalfWriteCount = 2

    /// The quiet period of the watcher of a registry: the watcher gives one
    /// change after the tree stays quiet this long.
    private static let quietPeriod = duration(of: DotfolderWatcher.defaultDebounceInterval)

    /// The count of the quiet periods in ``splitPause``.
    private static let quietPeriodsInSplitPause = 2

    /// The pause between the two halves of a split burst. It is longer than
    /// one quiet period, thus the watcher gives one change for each half.
    private static let splitPause = quietPeriod * quietPeriodsInSplitPause

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

    @Test(
        """
        a burst of writes ends with the last state, and no catalog with an older state comes after it, \
        also when the burst spans two quiet periods
        """,
        .timeLimit(.minutes(1)),
        arguments: [Duration.zero, splitPause])
    func burstOfWritesEndsWithTheLastState(pauseBetweenHalves pause: Duration) async throws {
        let layer = try Self.layerWithAgent()
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer], watch: true)
        try await registry.load()
        let reloads = registry.onReload
        let lastID = try #require(Self.burstAgentIDs.last)
        let fullIDs = ([Self.agentID] + Self.burstAgentIDs).sorted()

        try Self.writeBurst(of: Self.burstAgentIDs.prefix(Self.firstHalfWriteCount), in: layer)
        try await Task.sleep(for: pause)
        try Self.writeBurst(of: Self.burstAgentIDs.dropFirst(Self.firstHalfWriteCount), in: layer)

        let published = try #require(await reloads.first { $0.definition(named: lastID) != nil })
        let later = try await Self.catalogsBeforeMarker(on: reloads, of: registry, in: layer)
        #expect(published.definitions.map(\.id) == fullIDs)
        #expect(Self.description(in: published) == lastID)
        #expect(later.map { $0.definitions.map(\.id) } == Array(repeating: fullIDs, count: later.count))
        #expect(later.map { Self.description(in: $0) } == Array(repeating: Optional(lastID), count: later.count))
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

    /// Writes one part of a burst. For each id, it writes a new description
    /// of the agent `agentID`, and then a new agent file named by the id.
    ///
    /// - Parameters:
    ///   - ids: The ids of the new agents, in the order of the writes.
    ///   - layer: The layer to write in.
    /// - Throws: The error of the file system.
    private static func writeBurst(of ids: some Sequence<String>, in layer: TemporaryLayer) throws {
        for id in ids {
            try layer.write(agentText(description: id), at: agentPath)
            try layer.write(agentText(named: id, description: id), at: filePath(of: id))
        }
    }

    /// Adds the agent `markerID`, reloads the registry, and gives each
    /// catalog that `reloads` gets before the first catalog with the marker.
    ///
    /// The marker gives the read a known end, thus the read has no time
    /// limit. `reload()` publishes a catalog with the marker before it
    /// returns. When a watcher build starts after the write and publishes
    /// first, its catalog also holds the marker.
    ///
    /// - Parameters:
    ///   - reloads: An `onReload` stream of `registry`.
    ///   - registry: The registry to reload.
    ///   - layer: The layer of the registry.
    /// - Returns: The catalogs before the first catalog with the marker, in
    ///   the order of `reloads`.
    /// - Throws: The error of the file system, or the error of `reload()`.
    private static func catalogsBeforeMarker(
        on reloads: AsyncStream<AgentCatalog>, of registry: AgentRegistry, in layer: TemporaryLayer
    ) async throws -> [AgentCatalog] {
        try layer.write(agentText(named: markerID, description: markerID), at: filePath(of: markerID))
        try await registry.reload()
        return await reloads
            .prefix { $0.definition(named: markerID) == nil }
            .reduce(into: []) { catalogs, catalog in catalogs.append(catalog) }
    }

    /// The path of the file of the agent `id`, relative to a layer root.
    ///
    /// - Parameter id: The name of the agent.
    /// - Returns: The path.
    private static func filePath(of id: String) -> String {
        "agents/\(id).md"
    }

    /// Gives `interval` as a `Duration`.
    ///
    /// - Parameter interval: A finite interval.
    /// - Returns: The same length of time.
    private static func duration(of interval: DispatchTimeInterval) -> Duration {
        let start = DispatchTime.now()
        return .nanoseconds((start + interval).uptimeNanoseconds - start.uptimeNanoseconds)
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
