import FoundationModelsExtras
import Synchronization

/// The catalog of agent definitions over a list of layers (plan.md §4.1,
/// §12).
///
/// The registry builds its catalog one time, when it is made, and keeps it.
/// `catalog()` does no I/O: it gives the cached value. `reload()` reads the
/// layers again, and swaps the new catalog in atomically. A caller that holds
/// a catalog keeps a value that does not change.
///
/// The registry keeps `layers` and `variables` for the render of a body at
/// run start (plan.md §4.3 step 3). Each definition names the layer that
/// gave it.
public final class AgentRegistry: Sendable {
    /// The layers of the catalog, lowest precedence first.
    public let layers: [DotfolderStack.Layer]

    /// The values that the render of each body interpolates.
    public let variables: [String: String]

    /// The current catalog.
    private let current: Mutex<AgentCatalog>

    /// Makes a registry over the layers of a `DotfolderStack`, and builds
    /// its catalog.
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
    /// Makes a registry over a list of layers, and builds its catalog.
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
    public init(layers: [DotfolderStack.Layer], variables: [String: String] = [:], watch: Bool = false) {
        self.layers = layers
        self.variables = variables
        self.current = Mutex(AgentCatalogBuilder.build(layers: layers))
    }

    /// Gives the cached catalog. This call does no I/O.
    ///
    /// - Returns: The catalog of the last build.
    public func catalog() -> AgentCatalog {
        current.withLock { $0 }
    }

    /// Reads the layers again, and swaps the new catalog in atomically.
    ///
    /// The build runs outside the lock. Thus a `catalog()` call during a
    /// reload gives the previous catalog, and never waits for the read of
    /// the files.
    public func reload() {
        let rebuilt = AgentCatalogBuilder.build(layers: layers)
        current.withLock { $0 = rebuilt }
    }
}
