import FoundationModelsExtras

/// Appends the change of each catalog that the registry swaps in to the
/// change log of the `agents` endpoint, in the order of the swaps
/// (EXTRAS-9 rule 9).
///
/// The registry swaps a build in under a lock, and ``ChangeLog`` is an
/// actor, thus the swap cannot append the change itself. The swap queues
/// the change here under its lock, thus the queue holds the changes in the
/// order of the swaps, and one task appends them in that order. Each call
/// of ``enqueue(_:)`` gives a stream that ends when the change is in the
/// log: the build that swapped the change in waits for it, thus after
/// `reload()` returns, the cursor of the log is the cursor of its change.
///
/// The task holds the stream of the queue and the change log, and never the
/// feed. The `deinit` of the feed finishes the queue and cancels the task.
final class AgentChangeFeed: Sendable {
    /// One change in the queue, and the signal that ends when the change is
    /// in the log.
    private struct Pending: Sendable {
        /// The change.
        let change: ChangedIDs

        /// The continuation of the stream that ``enqueue(_:)`` gave for the
        /// change.
        let appended: AsyncStream<Void>.Continuation
    }

    /// The continuation of the queue.
    private let queue: AsyncStream<Pending>.Continuation

    /// The task that appends each queued change to the log.
    private let task: Task<Void, Never>

    /// Starts to feed a change log.
    ///
    /// - Parameter changeLog: The change log that gets each queued change.
    init(changeLog: ChangeLog<ChangedIDs>) {
        let (stream, queue) = AsyncStream<Pending>.makeStream()
        self.queue = queue
        task = Task {
            for await pending in stream {
                await changeLog.append(pending.change)
                pending.appended.finish()
            }
        }
    }

    /// Finishes the queue and cancels the task.
    deinit {
        queue.finish()
        task.cancel()
    }

    /// Queues one change. The caller holds the lock of the swap that made the
    /// change, thus the log takes the changes in the order of the swaps.
    ///
    /// - Parameter change: The change of one swap.
    /// - Returns: A stream that ends when the change is in the log.
    func enqueue(_ change: ChangedIDs) -> AsyncStream<Void> {
        let (appended, signal) = AsyncStream<Void>.makeStream()
        if case .terminated = queue.yield(Pending(change: change, appended: signal)) {
            signal.finish()
        }
        return appended
    }
}
