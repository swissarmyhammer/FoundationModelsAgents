import Foundation
import FoundationModelsExtras
import Synchronization

extension AgentRegistry {
    /// Each new catalog of the registry.
    ///
    /// Each access makes a subscription of its own. Thus two readers each get
    /// each catalog. The stream gets each catalog that a build swaps in after
    /// the access: the build of `load()`, of `reload()`, of a watcher change,
    /// and of a `layerUpdates` value. A burst of changes gives one final
    /// catalog, which holds the last state of the files.
    ///
    /// A build publishes its catalog here before the change log of the
    /// `agents` endpoint has the change of the catalog. Thus a reader that
    /// reads the root `cursor` of the endpoint at once for a catalog of this
    /// stream can get the cursor before that change. A subscription to
    /// `changes(after:)` with that cursor then gives the change of the
    /// catalog again: the reader sees a change two times, and never misses
    /// one. The `reload()` call of the build returns after the change is in
    /// the log.
    ///
    /// The stream finishes when the registry is released.
    public var onReload: AsyncStream<AgentCatalog> {
        reloads.subscribe()
    }

    /// Stops the follow of the changes: the watcher of the layer roots and
    /// the task of the `layerUpdates` values of the provider.
    ///
    /// A host calls it when it does not use the registry for a time but
    /// keeps it, for example for a closed session. After the call, a change
    /// of a layer gives no reload and no new catalog. `catalog()` gives the
    /// last catalog. A later `load()` or `reload()` reads the files again and
    /// publishes its catalog, but it does not start a watcher again.
    ///
    /// The call waits until a reload that a change started is complete.
    /// Thus no catalog of a change comes after the call returns.
    ///
    /// A second call does nothing. A call before `load()` stops the registry
    /// before it watches. A registry with `watch: false` and no provider
    /// follows no change, thus the call does nothing.
    public func stopWatching() async {
        await reloads.stop()
    }
}

/// Follows the changes of the layers of one `AgentRegistry`, and publishes
/// each new catalog.
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
/// `stop()` stops the watcher and the two tasks, and no later call starts
/// them again. The `deinit` stops the watcher, cancels the two tasks, and
/// finishes each `onReload` stream. The task that calls `reload()` keeps a weak reference to
/// the registry. Thus the registry is released when the host releases it.
final class AgentReloadLoop: Sendable {
    /// The watcher of the watched roots.
    private struct Watch {
        /// The roots that the watcher watches, in layer order.
        fileprivate let roots: [URL]

        /// The watcher, which is started.
        fileprivate let watcher: DotfolderWatcher
    }

    /// The tasks of a loop that follows the changes.
    private struct Following {
        /// The task that calls `reload()` for each request.
        fileprivate let requestTask: Task<Void, Never>

        /// The task that makes a request for each `layerUpdates` value, or
        /// `nil` for a registry with no marketplace provider.
        fileprivate let updatesTask: Task<Void, Never>?

        /// Cancels the two tasks.
        fileprivate func cancel() {
            updatesTask?.cancel()
            requestTask.cancel()
        }
    }

    /// What the loop does now.
    private enum Phase {
        /// No build ran yet. Nothing reads the request stream.
        case waiting(requests: AsyncStream<Void>)

        /// A build ran, and the tasks follow the requests and the updates.
        case following(Following)

        /// `stop()` ran. Nothing follows the changes, and nothing starts to.
        case stopped
    }

    /// The watch of the loop.
    private enum WatchState {
        /// No watcher runs, and a build can start one.
        case idle

        /// A watcher runs.
        case watching(Watch)

        /// `stop()` ran. No watcher runs, and no build starts one.
        case stopped

        /// The watcher that runs, or `nil`.
        fileprivate var watcher: DotfolderWatcher? {
            guard case .watching(let watch) = self else { return nil }
            return watch.watcher
        }

        /// The roots that the watcher watches, or `nil`.
        fileprivate var roots: [URL]? {
            guard case .watching(let watch) = self else { return nil }
            return watch.roots
        }

        /// Stops the watcher that runs, and changes to `next`.
        ///
        /// - Parameter next: The state after the stop.
        fileprivate mutating func stopWatcher(then next: WatchState) {
            watcher?.stop()
            self = next
        }
    }

    /// The continuation of the request stream.
    private let requests: AsyncStream<Void>.Continuation

    /// The broadcaster of `onReload`.
    private let broadcaster = AgentCatalogBroadcaster()

    /// What the loop does now.
    private let phase: Mutex<Phase>

    /// The current watch.
    private let currentWatch = Mutex(WatchState.idle)

    /// Makes a loop that does not follow the changes yet. It reads no file.
    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        requests = continuation
        phase = Mutex(.waiting(requests: stream))
    }

    /// Stops the watcher, cancels the tasks, and finishes each `onReload`
    /// stream.
    deinit {
        halt()
        requests.finish()
        broadcaster.finishAll()
    }

    /// Whether a watcher watches roots now.
    var isWatching: Bool {
        currentWatch.withLock { $0.watcher != nil }
    }

    /// Stops the watcher and the two tasks, and waits until the request task
    /// ends. Thus a reload that a request started is complete when the call
    /// returns. No later `follow` or `watch` call starts them again. A second
    /// call does nothing.
    func stop() async {
        await halt()?.requestTask.value
    }

    /// Stops the watcher, cancels the two tasks, and changes the watch and
    /// the phase to `stopped`. It does not wait, thus `deinit` and `stop()`
    /// share it.
    ///
    /// - Returns: The cancelled tasks, or `nil` when no build ran or the loop
    ///   was stopped before.
    @discardableResult
    private func halt() -> Following? {
        currentWatch.withLock { $0.stopWatcher(then: .stopped) }
        let following = phase.withLock { phase -> Following? in
            defer { phase = .stopped }
            guard case .following(let following) = phase else { return nil }
            return following
        }
        following?.cancel()
        return following
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
    /// provider gives a new watchable layer. After `stop()` it does nothing.
    ///
    /// - Parameter roots: The roots to watch, in layer order, or `nil` for no
    ///   watch.
    func watch(roots: [URL]?) {
        currentWatch.withLock { current in
            if case .stopped = current { return }
            guard current.roots != roots else { return }
            current.stopWatcher(then: roots.map { .watching(startWatch(of: $0)) } ?? .idle)
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
