import Foundation
import FoundationModelsExtras
import Synchronization

extension AgentRegistry {
    /// Each new catalog of the registry (plan.md §4.1).
    ///
    /// Each access makes a subscription of its own. Thus two readers each get
    /// each catalog. The stream gets each catalog that a build swaps in after
    /// the access: the build of `load()`, of `reload()`, of a watcher change,
    /// and of a `layerUpdates` value. A burst of changes gives one final
    /// catalog, which holds the last state of the files.
    ///
    /// The stream finishes when the registry is released.
    public var onReload: AsyncStream<AgentCatalog> {
        reloads.subscribe()
    }
}

/// Follows the changes of the layers of one `AgentRegistry`, and publishes
/// each new catalog (plan.md §4.1).
///
/// The `init` of the loop makes a stream of reload requests and reads no
/// file. Each build of the registry calls `follow(registry:layerUpdates:)`
/// before it reads the provider, and `watch(roots:)` before it reads the agent
/// files. Thus a change during the build gives one more reload, and the build
/// loses no change.
///
/// The first `follow` call starts one task that calls `reload()` for each
/// request, and one task that makes a request for each `layerUpdates` value.
/// `watch(roots:)` keeps a `DotfolderWatcher` that makes a request for each
/// change of a watched root.
///
/// The request stream keeps one request at the most. Thus a burst of
/// requests while a reload runs gives one more reload, and that reload reads
/// the last state of the files.
///
/// The `deinit` stops the watcher, cancels the two tasks, and finishes each
/// `onReload` stream. The task that calls `reload()` keeps a weak reference to
/// the registry. Thus the registry is released when the host releases it.
final class AgentReloadLoop: Sendable {
    /// The watcher of the watched roots.
    private struct Watch {
        /// The roots that the watcher watches, in layer order.
        let roots: [URL]

        /// The watcher, which is started.
        let watcher: DotfolderWatcher
    }

    /// The tasks of a loop that follows the changes.
    private struct Following {
        /// The task that calls `reload()` for each request.
        let requestTask: Task<Void, Never>

        /// The task that makes a request for each `layerUpdates` value, or
        /// `nil` for a registry with no marketplace provider.
        let updatesTask: Task<Void, Never>?
    }

    /// What the loop does now.
    private enum Phase {
        /// No build ran yet. Nothing reads the request stream.
        case waiting(requests: AsyncStream<Void>)

        /// A build ran, and the tasks follow the requests and the updates.
        case following(Following)
    }

    /// The continuation of the request stream.
    private let requests: AsyncStream<Void>.Continuation

    /// The broadcaster of `onReload`.
    private let broadcaster = AgentCatalogBroadcaster()

    /// What the loop does now.
    private let phase: Mutex<Phase>

    /// The current watch, or `nil` when the loop watches no root.
    private let currentWatch = Mutex<Watch?>(nil)

    /// Makes a loop that does not follow the changes yet. It reads no file.
    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        requests = continuation
        phase = Mutex(.waiting(requests: stream))
    }

    /// Stops the watcher, cancels the tasks, and finishes each `onReload`
    /// stream.
    deinit {
        currentWatch.withLock { $0?.watcher.stop() }
        phase.withLock { phase in
            guard case .following(let following) = phase else { return }
            following.requestTask.cancel()
            following.updatesTask?.cancel()
        }
        requests.finish()
        broadcaster.finishAll()
    }

    /// Makes a new `onReload` stream.
    ///
    /// - Returns: A stream that gets each catalog that `publish(_:)` gives
    ///   after this call.
    func subscribe() -> AsyncStream<AgentCatalog> {
        broadcaster.subscribe()
    }

    /// Gives a new catalog to each `onReload` stream.
    ///
    /// - Parameter catalog: The catalog that a build swapped in.
    func publish(_ catalog: AgentCatalog) {
        broadcaster.publish(catalog)
    }

    /// Starts to follow the requests and the `layerUpdates` values. Only the
    /// first call does work.
    ///
    /// - Parameters:
    ///   - registry: The registry to reload. The loop keeps a weak reference.
    ///   - layerUpdates: Gives the `layerUpdates` stream of the provider, or
    ///     `nil` for no provider. Each access of `layerUpdates` makes a
    ///     subscription, thus the loop calls this one time only.
    func follow(registry: AgentRegistry, layerUpdates: () -> AsyncStream<Void>?) {
        phase.withLock { phase in
            guard case .waiting(let stream) = phase else { return }
            phase = .following(
                Following(
                    requestTask: Self.startRequestTask(over: stream, reloading: registry),
                    updatesTask: layerUpdates().map(startUpdatesTask(over:))))
        }
    }

    /// Watches `roots`. It keeps the current watcher when it watches the same
    /// roots, and replaces it when the roots changed, for example when a
    /// provider gives a new watchable layer.
    ///
    /// - Parameter roots: The roots to watch, in layer order, or `nil` for no
    ///   watch.
    func watch(roots: [URL]?) {
        currentWatch.withLock { current in
            guard current?.roots != roots else { return }
            current?.watcher.stop()
            current = roots.map(startWatch(of:))
        }
    }

    /// Starts the task that calls `reload()` for each request.
    ///
    /// - Parameters:
    ///   - stream: The request stream.
    ///   - registry: The registry to reload. The task keeps a weak
    ///     reference.
    /// - Returns: The task. It ends when the stream finishes, when the
    ///   registry is released, or when the task is cancelled.
    private static func startRequestTask(
        over stream: AsyncStream<Void>, reloading registry: AgentRegistry
    ) -> Task<Void, Never> {
        Task { [weak registry] in
            for await _ in stream {
                guard await reload(registry) else { return }
            }
        }
    }

    /// Reloads the registry for one request.
    ///
    /// - Parameter registry: The registry, or `nil` when it was released.
    /// - Returns: `true` when the reload ran. `false` when the registry was
    ///   released or the task was cancelled, thus the request task ends.
    private static func reload(_ registry: AgentRegistry?) async -> Bool {
        guard let registry else { return false }
        do {
            try await registry.reload()
            return true
        } catch {
            return false
        }
    }

    /// Starts the task that makes a request for each `layerUpdates` value.
    ///
    /// - Parameter updates: The `layerUpdates` stream of the provider.
    /// - Returns: The task. It ends when the stream finishes or when the task
    ///   is cancelled.
    private func startUpdatesTask(over updates: AsyncStream<Void>) -> Task<Void, Never> {
        Task { [requests] in
            for await _ in updates {
                requests.yield()
            }
        }
    }

    /// Starts a watcher over `roots` that makes a request for each change.
    ///
    /// - Parameter roots: The roots to watch, in layer order.
    /// - Returns: The watch, which is started.
    private func startWatch(of roots: [URL]) -> Watch {
        let watcher = DotfolderWatcher(roots: roots) { [requests] in
            requests.yield()
        }
        watcher.start()
        return Watch(roots: roots, watcher: watcher)
    }
}
