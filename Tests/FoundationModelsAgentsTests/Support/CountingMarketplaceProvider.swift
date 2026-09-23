import Marketplace
import Synchronization

/// A marketplace provider that counts each call of `marketplaceLayers()`, and
/// gives the layers of the provider that it wraps.
///
/// A test uses it to show that no `init` of `AgentRegistry` asks the provider
/// for its layers, and that `load()` asks one time (plan.md §4.1).
final class CountingMarketplaceProvider: MarketplaceLayerProviding {
    /// The provider that gives the layers.
    private let wrapped: any MarketplaceLayerProviding

    /// The count of the calls of `marketplaceLayers()`.
    private let calls = Mutex(0)

    /// Makes a provider that counts the calls to `wrapped`.
    ///
    /// - Parameter wrapped: The provider that gives the layers.
    init(wrapping wrapped: any MarketplaceLayerProviding) {
        self.wrapped = wrapped
    }

    /// The count of the calls of `marketplaceLayers()` until now.
    var callCount: Int {
        calls.withLock { $0 }
    }

    /// Counts the call, and gives the layers of the wrapped provider.
    ///
    /// - Returns: The layers of the wrapped provider, lowest precedence first.
    func marketplaceLayers() -> [MarketplaceLayer] {
        calls.withLock { $0 += 1 }
        return wrapped.marketplaceLayers()
    }

    /// The updates of the wrapped provider.
    var layerUpdates: AsyncStream<Void> {
        wrapped.layerUpdates
    }
}
