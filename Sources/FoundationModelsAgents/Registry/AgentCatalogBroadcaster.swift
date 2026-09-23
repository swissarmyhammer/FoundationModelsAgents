import Synchronization

/// Gives each catalog that it publishes to each current subscriber
/// (plan.md §4.1).
///
/// Two `for await` loops over one `AsyncStream` divide its values between
/// them. Thus each `subscribe()` call makes a stream of its own, and
/// `publish(_:)` yields the catalog to each of those streams.
///
/// The table of subscribers is in a `Mutex`. Thus the class is `Sendable`,
/// and the compiler checks it.
final class AgentCatalogBroadcaster: Sendable {
    /// The current subscribers, and the id that the next subscriber gets.
    private struct Subscribers {
        /// The continuation of each current subscriber, by id.
        var continuations: [Int: AsyncStream<AgentCatalog>.Continuation] = [:]

        /// The id of the next subscriber.
        var nextID = 0
    }

    /// The subscribers of this broadcaster.
    private let subscribers = Mutex(Subscribers())

    /// Makes a new subscriber stream. The stream gets each catalog that
    /// `publish(_:)` gives after this call.
    ///
    /// - Returns: The stream of the subscriber. It finishes when the caller
    ///   cancels it or releases it, or when `finishAll()` runs.
    func subscribe() -> AsyncStream<AgentCatalog> {
        let (stream, continuation) = AsyncStream<AgentCatalog>.makeStream()
        let id = subscribers.withLock { state in
            let id = state.nextID
            state.nextID += 1
            state.continuations[id] = continuation
            return id
        }
        continuation.onTermination = { [weak self] _ in self?.unsubscribe(id: id) }
        return stream
    }

    /// Gives one catalog to each current subscriber.
    ///
    /// - Parameter catalog: The catalog to give.
    func publish(_ catalog: AgentCatalog) {
        for continuation in subscribers.withLock({ Array($0.continuations.values) }) {
            continuation.yield(catalog)
        }
    }

    /// Finishes each current subscriber stream.
    func finishAll() {
        let current = subscribers.withLock { state in
            defer { state.continuations.removeAll() }
            return Array(state.continuations.values)
        }
        for continuation in current {
            continuation.finish()
        }
    }

    /// Removes the continuation of one subscriber when its stream ends. Thus
    /// a cancelled or released subscriber keeps no slot.
    ///
    /// - Parameter id: The id of the subscriber to remove.
    private func unsubscribe(id: Int) {
        subscribers.withLock { _ = $0.continuations.removeValue(forKey: id) }
    }
}
