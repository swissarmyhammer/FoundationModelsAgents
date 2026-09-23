import Foundation
import FoundationModelsExtras
import Marketplace
import Synchronization

/// The catalog of agent definitions over the marketplace layers and the local
/// layers (plan.md §4.1, §6.1, §12).
///
/// The layers are `marketplace[0] < … < marketplace[n] < local layers`. The
/// marketplace layers come from `MarketplaceLayerProviding.marketplaceLayers()`,
/// and the local layers come from the host.
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
/// run start (plan.md §4.3 step 3). Each definition names the layer that
/// gave it, and a marketplace definition also keeps its marketplace layer and
/// its `MarketplaceProvenance`.
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
    /// catalog. It is the empty build until the first `load()`.
    private let current: Mutex<Generation>

    /// The number of the last build that started. A build swaps in only when
    /// its number is larger than the number of the current build. Thus an
    /// earlier build that ends last does not replace a later build.
    private let lastBuildNumber = Mutex(Generation.empty.number)

    /// The loop that follows the changes and publishes `onReload`.
    let reloads = AgentReloadLoop()

    /// The marketplace layers of the last build, lowest precedence first.
    /// It is empty before the first `load()`.
    public var marketplaceLayers: [MarketplaceLayer] {
        current.withLock { $0.marketplaceLayers }
    }

    /// The layers of the last build, lowest precedence first: each
    /// marketplace layer, then each local layer. The `layerIndex` of the
    /// provenance of a definition of the same build is a position in this
    /// list.
    public var layers: [DotfolderStack.Layer] {
        marketplaceLayers.map(\.layer) + localLayers
    }

    /// Makes a registry over the layers of a `DotfolderStack`. It reads no
    /// file: call `load()` to build the catalog.
    ///
    /// - Parameters:
    ///   - stack: The dotfolder stack. Its layers are the layers of the
    ///     catalog: `defaults < user < project`.
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
    /// A host that wants `~/.claude` appends a layer to the list.
    ///
    /// - Parameters:
    ///   - layers: The layers of the catalog, lowest precedence first. The
    ///     highest layer that holds a path wins it.
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
    /// The build reads the `.md` files directly in `agents/` of each layer
    /// of `marketplaces.marketplaceLayers()`, one level. A marketplace layer
    /// with no `agents/` folder gives no agent. A local copy of a file name
    /// wins over a marketplace copy, with one advisory.
    ///
    /// The first `load()` takes the `layerUpdates` stream of the provider.
    /// Each value calls `reload()`, also when `watch` is `false`.
    ///
    /// - Parameters:
    ///   - marketplaces: The provider of the marketplace layers. Its layers
    ///     are below the layers of `stack`.
    ///   - stack: The dotfolder stack. Its layers are the local layers:
    ///     `defaults < user < project`.
    ///   - variables: The values that the render of each body interpolates.
    ///     The default is no values.
    ///   - watch: Whether to rebuild the catalog when a layer changes. The
    ///     default is `false`. With `true`, the first `load()` starts a
    ///     `DotfolderWatcher` over each local layer root and over the root of
    ///     each marketplace layer that `isWatchable` marks. Each change calls
    ///     `reload()`.
    public convenience init(
        marketplaces: any MarketplaceLayerProviding, stack: DotfolderStack,
        variables: [String: String] = [:], watch: Bool = false
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
        self.current = Mutex(.empty)
    }

    /// Gives the cached catalog. This call does no I/O.
    ///
    /// - Returns: The catalog of the last build, or an empty catalog before
    ///   the first `load()`.
    public func catalog() -> AgentCatalog {
        current.withLock { $0.catalog }
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
        try build()
    }

    /// Asks the provider for its layers again, reads the agent files again,
    /// and swaps the new catalog in atomically.
    ///
    /// Agent files change while the host runs, thus this is a normal path.
    /// A watcher change and a `layerUpdates` value call it too. The build
    /// runs outside the lock. Thus a `catalog()` call during a reload gives
    /// the previous catalog, and never waits for the read of the files.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   build. The catalog then does not change.
    public func reload() async throws {
        try build()
    }

    /// Reads the layers of the provider and the local layers, swaps the new
    /// build in, and publishes its catalog on `onReload`. `load()` and
    /// `reload()` share this build.
    ///
    /// The build starts to follow the changes before it reads the provider,
    /// and watches the roots before it reads the agent files. Thus a change
    /// during the build gives one more reload.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   build.
    private func build() throws {
        try Task.checkCancellation()
        let number = lastBuildNumber.withLock { last in
            last += 1
            return last
        }
        reloads.follow(registry: self) { [marketplaces] in marketplaces?.layerUpdates }
        let marketplaceLayers = marketplaces?.marketplaceLayers() ?? []
        reloads.watch(roots: watchedRoots(marketplaceLayers: marketplaceLayers))
        let rebuilt = Generation.read(number: number, marketplaceLayers: marketplaceLayers, localLayers: localLayers)
        current.withLock { current in
            guard rebuilt.number > current.number else { return }
            current = rebuilt
            reloads.publish(rebuilt.catalog)
        }
    }

    /// The roots that the watcher watches: the root of each marketplace
    /// layer that `isWatchable` marks, then the root of each local layer.
    ///
    /// - Parameter marketplaceLayers: The marketplace layers of the build.
    /// - Returns: The roots in layer order, or `nil` when `watch` is `false`.
    private func watchedRoots(marketplaceLayers: [MarketplaceLayer]) -> [URL]? {
        guard watch else { return nil }
        return marketplaceLayers.filter(\.isWatchable).map(\.layer.root) + localLayers.map(\.root)
    }

    /// One build of the registry: its number, the marketplace layers that
    /// the build read, and the catalog of those layers and the local layers.
    private struct Generation: Sendable {
        /// The build before the first `load()`: number zero, no marketplace
        /// layer, and an empty catalog.
        static let empty = Generation(
            number: .zero, marketplaceLayers: [], catalog: AgentCatalog(definitions: [], diagnostics: []))

        /// The number of the build. A later build has a larger number.
        let number: Int

        /// The marketplace layers of the build, lowest precedence first.
        let marketplaceLayers: [MarketplaceLayer]

        /// The catalog of the build.
        let catalog: AgentCatalog

        /// Builds the catalog of the marketplace layers and the local layers.
        ///
        /// - Parameters:
        ///   - number: The number of the build.
        ///   - marketplaceLayers: The marketplace layers, lowest precedence
        ///     first.
        ///   - localLayers: The local layers, lowest precedence first.
        /// - Returns: The build of those layers.
        static func read(
            number: Int, marketplaceLayers: [MarketplaceLayer], localLayers: [DotfolderStack.Layer]
        ) -> Generation {
            Generation(
                number: number,
                marketplaceLayers: marketplaceLayers,
                catalog: AgentCatalogBuilder.build(marketplaceLayers: marketplaceLayers, localLayers: localLayers))
        }
    }
}
