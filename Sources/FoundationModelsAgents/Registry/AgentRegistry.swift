import Foundation
import FoundationModelsExtras
import Marketplace
import Synchronization

/// The catalog of agent definitions over the marketplace layers and the
/// local layers.
///
/// The layers are `marketplace[0] < … < marketplace[n]`, then the local
/// layers in the order of the `DotfolderStack` of the host, for example
/// `defaults < user < project`. The marketplace layers come from
/// `MarketplaceLayerProviding.marketplaceLayers()`, and the local layers come
/// from the host. No layer goes between two local layers.
///
/// Each local layer holds its agents in two forms. The dotfolder form is
/// `agents/<id>/AGENT.md`. The agent folder form is `<id>/AGENT.md`, and the
/// root `AGENT.md` of the layer is the default agent, with the fixed id
/// ``AgentCatalog/defaultAgentID``. A child folder of the layer root whose
/// name is not a valid id, for example `_skills/`, is not an agent. A host
/// gives its root settings folder as one layer of its stack, for example the
/// `user` layer, and the folder of the session as the `project` layer, which
/// wins. The package holds no code of a sync service: a host that syncs a
/// folder gives its URL as a layer.
///
/// Each `init` stores its inputs and reads no file. `load()` asks the
/// provider for its layers, reads the agent files, and swaps the catalog in.
/// `load()` is `async`, thus each call site shows the I/O. A host calls
/// `load()` one time, after `market.start()`. Agent files change while the
/// host runs, thus `reload()` is a normal path: it does the same build
/// again. `catalog()` does no I/O: it gives the cached value, and it gives an
/// empty catalog before the first `load()`. A caller that holds a catalog
/// keeps a value that does not change.
///
/// The first build also starts to follow the changes. It follows each
/// `layerUpdates` value of the provider. With `watch: true`, a
/// `DotfolderWatcher` also watches each local layer root and each watchable
/// marketplace layer root. Each change calls `reload()`, and `onReload`
/// publishes each new catalog. The registry stops the watcher when the host
/// releases the registry.
///
/// The registry keeps `layers` and `variables` for the render of a body at
/// run start. Each definition names the layer that gave it, and a
/// marketplace definition also keeps its marketplace layer and its
/// `MarketplaceProvenance`.
public final class AgentRegistry: Sendable {
    /// The local layers of the catalog, lowest precedence first. They are
    /// above each marketplace layer.
    public let localLayers: [DotfolderStack.Layer]

    /// The values that the render of each body interpolates.
    public let variables: [String: String]

    /// Whether a watcher watches the layer roots after the first build.
    private let watch: Bool

    /// The provider of the marketplace layers, or `nil` for a registry with
    /// local layers only.
    private let marketplaces: (any MarketplaceLayerProviding)?

    /// The current build: the marketplace layers that it read, and its
    /// catalog. It is the empty build until the first `load()`. The `agents`
    /// endpoint of the registry reads its catalog here.
    let currentBuild = CurrentBuild()

    /// The one `agents` endpoint of the registry (EXTRAS-9 rule 1).
    private let graphPort: AgentsGraphPort

    /// The number of the last build that started. A build swaps in only when
    /// its number is larger than the number of the current build. Thus an
    /// earlier build that ends last does not replace a later build.
    private let lastBuildNumber = Mutex(Generation.empty.number)

    /// The loop that follows the changes and publishes `onReload`.
    let reloads = AgentReloadLoop()

    /// The marketplace layers of the last build, lowest precedence first.
    /// It is empty before the first `load()`.
    public var marketplaceLayers: [MarketplaceLayer] {
        currentBuild.marketplaceLayers
    }

    /// The layers of the last build, lowest precedence first: each
    /// marketplace layer, then each local layer in the order of the stack.
    /// The `layerIndex` of the provenance of a definition of the same build
    /// is a position in this list.
    public var layers: [DotfolderStack.Layer] {
        AgentCatalogLayer.ordered(marketplaceLayers: marketplaceLayers, localLayers: localLayers).map(\.layer)
    }

    /// Makes a registry over the layers of a `DotfolderStack`. It reads no
    /// file: call `load()` to build the catalog.
    ///
    /// - Parameters:
    ///   - stack: The dotfolder stack. Its layers are the layers of the
    ///     catalog, for example `defaults < user < project`.
    ///   - variables: The values that the render of each body interpolates.
    ///     The default is no values.
    ///   - watch: Whether to rebuild the catalog when a layer root changes.
    ///     The default is `false`. See `init(layers:variables:watch:)`.
    public convenience init(stack: DotfolderStack, variables: [String: String] = [:], watch: Bool = false) {
        self.init(layers: stack.layers, variables: variables, watch: watch)
    }

    /// Makes a registry over a list of layers. It reads no file: call
    /// `load()` to build the catalog.
    ///
    /// A host that wants `~/.claude` appends a layer to the list. A host with
    /// a root settings folder gives it as a layer, for example as the `user`
    /// layer below the `project` layer.
    ///
    /// - Parameters:
    ///   - layers: The layers of the catalog, lowest precedence first. The
    ///     highest layer that holds an agent wins it. Each layer holds its
    ///     agents as `agents/<id>/AGENT.md` and as `<id>/AGENT.md`, with the
    ///     default agent at `AGENT.md`. A layer root that does not exist
    ///     gives no agent and no diagnostic.
    ///   - variables: The values that the render of each body interpolates.
    ///     The default is no values.
    ///   - watch: Whether to rebuild the catalog when a layer root changes.
    ///     The default is `false`. With `true`, the first `load()` starts a
    ///     `DotfolderWatcher` over each layer root. Each change calls
    ///     `reload()`.
    public convenience init(
        layers: [DotfolderStack.Layer], variables: [String: String] = [:], watch: Bool = false
    ) {
        self.init(marketplaces: nil, localLayers: layers, variables: variables, watch: watch)
    }

    /// Makes a registry over the layers of a marketplace provider and the
    /// layers of a `DotfolderStack`. It reads no file and does not call
    /// `marketplaces.marketplaceLayers()`: call `load()` to build the
    /// catalog.
    ///
    /// The build reads each agent folder `agents/<id>/AGENT.md` of each
    /// layer of `marketplaces.marketplaceLayers()`. A marketplace layer with
    /// no `agents/` folder gives no agent. A local copy of an agent folder
    /// wins over a marketplace copy, with one advisory.
    ///
    /// The first `load()` takes the `layerUpdates` stream of the provider.
    /// Each value calls `reload()`, also when `watch` is `false`.
    ///
    /// - Parameters:
    ///   - marketplaces: The provider of the marketplace layers. Its layers
    ///     are below the layers of `stack`.
    ///   - stack: The dotfolder stack. Its layers are the local layers, for
    ///     example `defaults < user < project`.
    ///   - variables: The values that the render of each body interpolates.
    ///     The default is no values.
    ///   - watch: Whether to rebuild the catalog when a layer changes. The
    ///     default is `false`. With `true`, the first `load()` starts a
    ///     `DotfolderWatcher` over each local layer root, and over the root
    ///     of each marketplace layer that `isWatchable` marks. Each change
    ///     calls `reload()`.
    public convenience init(
        marketplaces: any MarketplaceLayerProviding, stack: DotfolderStack, variables: [String: String] = [:],
        watch: Bool = false
    ) {
        self.init(marketplaces: marketplaces, localLayers: stack.layers, variables: variables, watch: watch)
    }

    /// Makes a registry that stores its inputs. It reads no file.
    ///
    /// - Parameters:
    ///   - marketplaces: The provider of the marketplace layers, or `nil`.
    ///   - localLayers: The local layers, lowest precedence first.
    ///   - variables: The values that the render of each body interpolates.
    ///   - watch: Whether a watcher watches the layer roots after the first
    ///     build.
    private init(
        marketplaces: (any MarketplaceLayerProviding)?, localLayers: [DotfolderStack.Layer],
        variables: [String: String], watch: Bool
    ) {
        self.marketplaces = marketplaces
        self.localLayers = localLayers
        self.variables = variables
        self.watch = watch
        graphPort = AgentsGraphPort(build: currentBuild)
    }

    /// Whether a build swapped a catalog in: `true` after the first
    /// `load()` or `reload()` that did not throw. This call does no I/O.
    ///
    /// Before the first build, the catalog is empty because the registry
    /// read no file, not because the layers hold no agent.
    public var isLoaded: Bool {
        currentBuild.isLoaded
    }

    /// Gives the cached catalog. This call does no I/O.
    ///
    /// - Returns: The catalog of the last build, or an empty catalog before
    ///   the first `load()`.
    public func catalog() -> AgentCatalog {
        currentBuild.catalog()
    }

    /// Gives the one `agents` endpoint of the registry (EXTRAS-9 rule 1).
    ///
    /// A host calls it to get the endpoint of the catalog with no `agents`
    /// tool, for example to list the endpoint of a session folder before a
    /// session starts. It is the same endpoint that each ``AgentsTool`` over
    /// the registry gives in `graphQLEndpoints`.
    ///
    /// The first call makes the endpoint, and each later call gives the same
    /// instance. Thus each `agents` tool over the registry, of each session
    /// and each run, gives the same endpoint. The endpoint reads the catalog
    /// of the registry, and it does not keep the registry: the host still
    /// releases the registry. This call does no I/O.
    ///
    /// - Returns: The endpoint.
    /// - Throws: An error of the schema builder.
    public func agentsGraph() throws -> AgentsGraph {
        try graphPort.endpoint()
    }

    /// Asks the provider for its layers, reads the agent files, and swaps the
    /// catalog in. A host calls it one time, after `market.start()`.
    ///
    /// This first build also starts to follow the `layerUpdates` values and,
    /// with `watch: true`, the changes of the layer roots.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   build. The catalog then does not change.
    public func load() async throws {
        try await build()
    }

    /// Asks the provider for its layers again, reads the agent files again,
    /// and swaps the new catalog in atomically.
    ///
    /// Agent files change while the host runs, thus this is a normal path.
    /// A watcher change and a `layerUpdates` value call it too. The build
    /// runs outside the lock. Thus a `catalog()` call during a reload gives
    /// the previous catalog, and never waits for the read of the files.
    ///
    /// A reload that changes an agent returns after its change is in the
    /// change log of the `agents` endpoint: the root `cursor` of the
    /// endpoint then is the cursor of that change. This also holds when the
    /// task is cancelled after the build started: the build swaps its
    /// catalog in, and the call waits for its change.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   build. The catalog then does not change.
    public func reload() async throws {
        try await build()
    }

    /// Reads the layers of the provider and the local layers, swaps the new
    /// build in, publishes its catalog on `onReload`, and waits until its
    /// change is in the change log of the `agents` endpoint. `load()` and
    /// `reload()` share this build.
    ///
    /// The build starts to follow the changes before it reads the provider,
    /// and watches the roots before it reads the agent files. Thus a change
    /// during the build gives one more reload.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   build.
    private func build() async throws {
        try Task.checkCancellation()
        let number = lastBuildNumber.withLock { last in
            last += 1
            return last
        }
        reloads.follow(registry: self) { [marketplaces] in marketplaces?.layerUpdates }
        let marketplaceLayers = marketplaces?.marketplaceLayers() ?? []
        reloads.watch(roots: watchedRoots(marketplaceLayers: marketplaceLayers))
        let rebuilt = Generation.read(number: number, marketplaceLayers: marketplaceLayers, localLayers: localLayers)
        await currentBuild.swapIn(rebuilt, publishing: reloads.publish)
    }

    /// The roots that the watcher watches: the root of each marketplace
    /// layer that `isWatchable` marks, then the root of each local layer.
    ///
    /// A sync engine that changes a file of a local layer from a different
    /// device gives a file change in the layer, and the watcher sees it. A
    /// host that gets a change notification of its own calls `reload()`.
    ///
    /// - Parameter marketplaceLayers: The marketplace layers of the build.
    /// - Returns: The roots, or `nil` when `watch` is `false`.
    private func watchedRoots(marketplaceLayers: [MarketplaceLayer]) -> [URL]? {
        guard watch else { return nil }
        return marketplaceLayers.filter(\.isWatchable).map(\.layer.root) + localLayers.map(\.root)
    }

    /// One build of the registry: its number, the marketplace layers that
    /// the build read, and the catalog of those layers and the local layers.
    fileprivate struct Generation: Sendable {
        /// The build before the first `load()`: number zero, no marketplace
        /// layer, and an empty catalog.
        fileprivate static let empty = Generation(
            number: .zero, marketplaceLayers: [], catalog: AgentCatalog(definitions: [], diagnostics: []))

        /// The number of the build. A later build has a larger number.
        fileprivate let number: Int

        /// The marketplace layers of the build, lowest precedence first.
        fileprivate let marketplaceLayers: [MarketplaceLayer]

        /// The catalog of the build.
        fileprivate let catalog: AgentCatalog

        /// Builds the catalog of the marketplace layers and the local layers.
        ///
        /// - Parameters:
        ///   - number: The number of the build.
        ///   - marketplaceLayers: The marketplace layers, lowest precedence
        ///     first.
        ///   - localLayers: The local layers, lowest precedence first.
        /// - Returns: The build of those layers.
        fileprivate static func read(
            number: Int, marketplaceLayers: [MarketplaceLayer], localLayers: [DotfolderStack.Layer]
        ) -> Generation {
            Generation(
                number: number,
                marketplaceLayers: marketplaceLayers,
                catalog: AgentCatalogBuilder.build(marketplaceLayers: marketplaceLayers, localLayers: localLayers))
        }
    }
}

extension AgentRegistry {
    /// The current build of one registry: the build that the last `load()`
    /// or `reload()` swapped in.
    ///
    /// The registry and its `agents` endpoint (``AgentsGraph``) share this
    /// object. The endpoint reads the catalog here and keeps no reference to
    /// the registry. Thus the registry owns its endpoint (``AgentsGraphPort``)
    /// with no reference cycle, and the host still releases the registry and
    /// stops its watcher.
    ///
    /// The build also holds the one change log of the registry, the source
    /// of the `changes(after:)` subscription and of the root `cursor` of the
    /// endpoint (EXTRAS-9 rule 9). Each endpoint over the registry reads that
    /// log, thus each gives the same cursor. The swap of a build computes its
    /// change under the lock of the swap, and the log takes the changes in
    /// the order of the swaps.
    final class CurrentBuild: Sendable {
        /// The number of the newest changes that the change log keeps. A
        /// cursor that is older than these changes gives `RESYNC_REQUIRED`.
        static let changeLogCapacity = 1024

        /// The build. It is the empty build until the first `load()`.
        private let generation = Mutex(Generation.empty)

        /// The change log of the catalog: one event for each swap that adds,
        /// changes or removes an agent.
        let changeLog: ChangeLog<ChangedIDs>

        /// The feed that appends the change of each swap to ``changeLog``.
        private let changeFeed: AgentChangeFeed

        /// Makes the empty build, and its change log with no event.
        init() {
            let changeLog = ChangeLog<ChangedIDs>(capacity: Self.changeLogCapacity)
            self.changeLog = changeLog
            changeFeed = AgentChangeFeed(changeLog: changeLog)
        }

        /// Whether a build swapped a catalog in. This call does no I/O.
        var isLoaded: Bool {
            loadedCatalog() != nil
        }

        /// Gives the catalog of the build after the first `load()`.
        ///
        /// - Returns: The catalog of the build, or `nil` before the first
        ///   `load()`: the empty catalog then does not tell that the layers
        ///   hold no agent.
        func loadedCatalog() -> AgentCatalog? {
            generation.withLock { $0.number > Generation.empty.number ? $0.catalog : nil }
        }

        /// The marketplace layers of the build, lowest precedence first. It is
        /// empty before the first `load()`.
        var marketplaceLayers: [MarketplaceLayer] {
            generation.withLock { $0.marketplaceLayers }
        }

        /// Gives the catalog of the build. This call does no I/O.
        ///
        /// - Returns: The catalog of the build, or an empty catalog before the
        ///   first `load()`.
        func catalog() -> AgentCatalog {
            generation.withLock { $0.catalog }
        }

        /// Swaps `rebuilt` in when it is later than the build, publishes its
        /// catalog, and queues its change for the change log, each under the
        /// same lock. Thus an earlier build that ends last does not replace a
        /// later build, and the catalogs and the changes go out in the order
        /// of their builds.
        ///
        /// The call returns after the change is in the change log, also when
        /// the task of the caller is cancelled: the swap is done, and its
        /// change is appended. A swap that changes no agent appends nothing.
        ///
        /// The catalog goes out on `publish` before its change is in the log.
        /// Thus a reader of `onReload` that reads the cursor at once can read
        /// the cursor before the change, and then gets that change again
        /// after that cursor: a duplicate, never a loss.
        ///
        /// - Parameters:
        ///   - rebuilt: The new build.
        ///   - publish: Publishes the catalog of a build that swapped in.
        fileprivate func swapIn(_ rebuilt: Generation, publishing publish: (AgentCatalog) -> Void) async {
            let appended = generation.withLock { current -> AsyncStream<Void>? in
                guard rebuilt.number > current.number else { return nil }
                let change = AgentCatalogChanges.change(from: current.catalog, to: rebuilt.catalog)
                current = rebuilt
                publish(rebuilt.catalog)
                return change.map(changeFeed.enqueue)
            }
            guard let appended else { return }
            await Self.wait(for: appended)
        }

        /// Waits until a stream of ``AgentChangeFeed/enqueue(_:)`` ends,
        /// whether or not the task of the caller is cancelled.
        ///
        /// The iteration of a stream ends at once on a cancelled task. Thus
        /// the iteration runs on a task of its own, which the cancellation of
        /// the caller does not reach, and the caller waits for its value. The
        /// stream ends when the feed appends the change, thus the task ends.
        ///
        /// - Parameter appended: The stream that ends when the change is in
        ///   the change log.
        private static func wait(for appended: AsyncStream<Void>) async {
            await Task { for await _ in appended {} }.value
        }
    }
}
