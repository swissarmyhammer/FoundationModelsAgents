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

    /// The provider of the marketplace layers, or `nil` for a registry with
    /// local layers only.
    private let marketplaces: (any MarketplaceLayerProviding)?

    /// The current build: the marketplace layers that it read, and its
    /// catalog. It is the empty build until the first `load()`.
    private let current: Mutex<Generation>

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

    // periphery:ignore:parameters watch
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
    ///     The default is `false`. This version does not watch the layer
    ///     roots yet, thus `reload()` is the one way to rebuild.
    public convenience init(
        layers: [DotfolderStack.Layer], variables: [String: String] = [:], watch: Bool = false
    ) {
        self.init(marketplaces: nil, localLayers: layers, variables: variables)
    }

    // periphery:ignore:parameters watch
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
    /// - Parameters:
    ///   - marketplaces: The provider of the marketplace layers. Its layers
    ///     are below the layers of `stack`.
    ///   - stack: The dotfolder stack. Its layers are the local layers:
    ///     `defaults < user < project`.
    ///   - variables: The values that the render of each body interpolates.
    ///     The default is no values.
    ///   - watch: Whether to rebuild the catalog when a layer changes. The
    ///     default is `false`. This version does not watch the layers or
    ///     `layerUpdates` yet, thus `reload()` is the one way to rebuild.
    public convenience init(
        marketplaces: any MarketplaceLayerProviding, stack: DotfolderStack,
        variables: [String: String] = [:], watch: Bool = false
    ) {
        self.init(marketplaces: marketplaces, localLayers: stack.layers, variables: variables)
    }

    /// Makes a registry that stores its inputs. It reads no file.
    ///
    /// - Parameters:
    ///   - marketplaces: The provider of the marketplace layers, or `nil`.
    ///   - localLayers: The local layers, lowest precedence first.
    ///   - variables: The values that the render of each body interpolates.
    private init(
        marketplaces: (any MarketplaceLayerProviding)?, localLayers: [DotfolderStack.Layer],
        variables: [String: String]
    ) {
        self.marketplaces = marketplaces
        self.localLayers = localLayers
        self.variables = variables
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
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   build. The catalog then does not change.
    public func load() async throws {
        try build()
    }

    /// Asks the provider for its layers again, reads the agent files again,
    /// and swaps the new catalog in atomically.
    ///
    /// Agent files change while the host runs, thus this is a normal path.
    /// The build runs outside the lock. Thus a `catalog()` call during a
    /// reload gives the previous catalog, and never waits for the read of
    /// the files.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   build. The catalog then does not change.
    public func reload() async throws {
        try build()
    }

    /// Reads the layers of the provider and the local layers, and swaps the
    /// new build in. `load()` and `reload()` share this build.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   build.
    private func build() throws {
        try Task.checkCancellation()
        let rebuilt = Generation.read(marketplaces: marketplaces, localLayers: localLayers)
        current.withLock { $0 = rebuilt }
    }

    /// One build of the registry: the marketplace layers that the build
    /// read, and the catalog of those layers and the local layers.
    private struct Generation: Sendable {
        /// The build before the first `load()`: no marketplace layer and an
        /// empty catalog.
        static let empty = Generation(
            marketplaceLayers: [], catalog: AgentCatalog(definitions: [], diagnostics: []))

        /// The marketplace layers of the build, lowest precedence first.
        let marketplaceLayers: [MarketplaceLayer]

        /// The catalog of the build.
        let catalog: AgentCatalog

        /// Reads the layers of `marketplaces`, and builds the catalog.
        ///
        /// - Parameters:
        ///   - marketplaces: The provider of the marketplace layers, or
        ///     `nil` for no marketplace layer.
        ///   - localLayers: The local layers, lowest precedence first.
        /// - Returns: The build of those layers.
        static func read(
            marketplaces: (any MarketplaceLayerProviding)?, localLayers: [DotfolderStack.Layer]
        ) -> Generation {
            let marketplaceLayers = marketplaces?.marketplaceLayers() ?? []
            return Generation(
                marketplaceLayers: marketplaceLayers,
                catalog: AgentCatalogBuilder.build(marketplaceLayers: marketplaceLayers, localLayers: localLayers))
        }
    }
}
