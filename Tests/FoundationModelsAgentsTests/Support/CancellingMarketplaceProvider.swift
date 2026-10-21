import Marketplace
import Synchronization

/// A marketplace provider with no layers that cancels the task of one build.
///
/// A build of the registry asks the provider for its layers on the task that
/// calls `load()` or `reload()`, after its check for cancellation and before
/// its swap. A test calls `cancelNextBuild()`, and the next call of
/// `marketplaceLayers()` cancels the task that makes it. Thus the build swaps
/// its catalog in on a cancelled task.
final class CancellingMarketplaceProvider: MarketplaceLayerProviding {
    /// Whether the next call of `marketplaceLayers()` cancels its task.
    private let cancelsNextCall = Mutex(false)

    /// Makes the next call of `marketplaceLayers()` cancel the task that
    /// makes it.
    func cancelNextBuild() {
        cancelsNextCall.withLock { $0 = true }
    }

    /// Cancels the current task when `cancelNextBuild()` asked for it, one
    /// time, and gives no layer.
    ///
    /// - Returns: No layer.
    func marketplaceLayers() -> [MarketplaceLayer] {
        let cancels = cancelsNextCall.withLock { cancels in
            defer { cancels = false }
            return cancels
        }
        if cancels {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return []
    }

    /// A stream that ends at once: the layers never change.
    var layerUpdates: AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
