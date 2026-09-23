import Marketplace
import Synchronization

/// A marketplace provider whose layers and `layerUpdates` values a test
/// gives by hand.
///
/// A test calls `signal()` to send one `layerUpdates` value to each
/// subscriber, as a store does after it installs a new snapshot. The
/// provider counts the subscriptions, thus a test can show when the
/// registry takes the `layerUpdates` stream.
final class SignalingMarketplaceProvider: MarketplaceLayerProviding {
    /// The layers and the subscribers of the provider.
    private struct State {
        /// The layers that `marketplaceLayers()` gives.
        let layers: [MarketplaceLayer]

        /// The continuation of each `layerUpdates` stream.
        var subscribers: [AsyncStream<Void>.Continuation] = []
    }

    /// The layers and the subscribers of the provider.
    private let state: Mutex<State>

    /// Makes a provider that gives `layers`.
    ///
    /// - Parameter layers: The marketplace layers, lowest precedence first.
    init(layers: [MarketplaceLayer]) {
        state = Mutex(State(layers: layers))
    }

    /// The count of the `layerUpdates` streams that a caller took.
    var subscriptionCount: Int {
        state.withLock { $0.subscribers.count }
    }

    /// Gives the layers of the provider.
    ///
    /// - Returns: The layers, lowest precedence first.
    func marketplaceLayers() -> [MarketplaceLayer] {
        state.withLock { $0.layers }
    }

    /// A new stream that gets each value that `signal()` sends.
    var layerUpdates: AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        state.withLock { $0.subscribers.append(continuation) }
        return stream
    }

    /// Sends one `layerUpdates` value to each subscriber.
    func signal() {
        for subscriber in state.withLock({ $0.subscribers }) {
            subscriber.yield()
        }
    }
}
