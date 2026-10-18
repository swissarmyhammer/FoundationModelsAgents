import FoundationModelsExtras
import FoundationModelsRouter
import Synchronization
import ULID

/// The work of one child session in the registry of its parent: the one
/// `WorkKind.childSession` lease of the `start agent` call that started the
/// child.
///
/// A subagent is one more background tool call. The call holds the child as
/// work of the parent session with one lease, whose id is the id of the
/// child session. The work of the child stays in the registry of the child,
/// and never goes into the registry of the parent.
///
/// The lease follows the work events of the child session:
///
/// - ``start()`` begins the lease when the drive of the child starts, before
///   the child gets its task prompt. Thus the parent has work before the
///   child gives its first output.
/// - `SessionEvent.workEnded` of the child ends the lease: the parent then
///   has no work for the child. When the child has an open question, the
///   child waits only for the user. Then the lease is suspended, not ended,
///   and the parent has no work for the child too.
/// - `SessionEvent.workStarted` of the child resumes a suspended lease, and
///   begins a new lease after an end. Thus new work of the child, for
///   example new mail or a run that settles, is work of the parent again.
/// - ``end()`` ends the lease when the drive of the child ends: the child
///   closed, failed or was cancelled. After that time, no event begins a
///   lease.
///
/// A run with no call context, for example a host-started run, has no parent
/// session, and holds no lease.
///
/// A class, because the drive and the follower of the run share it. A
/// `Mutex` guards the state, thus the `Sendable` conformance is
/// compiler-checked.
final class ChildSessionWork: Sendable {
    /// The step of the lease.
    private enum Phase {
        /// The drive of the child did not start. No event begins a lease.
        case notStarted

        /// The lease is open: the child works.
        case open(BackgroundWork)

        /// The lease is suspended: the child waits only for the user.
        case suspended(BackgroundWork)

        /// The child has no work, and no lease is open.
        case noWork

        /// The drive of the child ended. No event begins a lease.
        case ended
    }

    /// The context of the `start agent` call in the parent, or `nil` for a
    /// run with no call. Each lease goes into the registry of its session.
    private let call: ToolContext?

    /// The id of the lease: the id of the child session.
    private let leaseID: String

    /// The step of the lease.
    private let phase: Mutex<Phase>

    /// Makes the work of the child `childSessionID` in the registry of the
    /// session of `call`, with no lease. ``start()`` begins the lease.
    ///
    /// - Parameters:
    ///   - call: The context of the `start agent` call that started the
    ///     child, or `nil` for a run with no call. That run holds no lease.
    ///   - childSessionID: The id of the child session. It is the id of the
    ///     lease.
    init(call: ToolContext?, childSessionID: ULID) {
        self.call = call
        self.leaseID = childSessionID.description
        self.phase = Mutex(.notStarted)
    }

    /// Begins the lease. The drive of the child calls it one time, before
    /// the task prompt. A second call, and a call after ``end()``, do
    /// nothing.
    func start() {
        phase.withLock { phase in
            guard case .notStarted = phase else { return }
            guard let call else {
                phase = .ended
                return
            }
            phase = .open(call.beginBackgroundWork(.childSession, id: leaseID))
        }
    }

    /// The lease that is open or suspended now, or `nil` when no lease is
    /// open.
    var lease: BackgroundWork? {
        phase.withLock { phase in
            switch phase {
            case .open(let lease), .suspended(let lease):
                lease
            case .notStarted, .noWork, .ended:
                nil
            }
        }
    }

    /// Changes the lease after one event of the child session. Only the work
    /// events change it.
    ///
    /// - Parameters:
    ///   - event: An event of the child session, in the order of its feed.
    ///   - hasOpenQuestion: Tells if the child has an open question. The
    ///     call reads it only for `SessionEvent.workEnded`.
    func observe(_ event: SessionEvent, hasOpenQuestion: @Sendable () async -> Bool) async {
        switch event {
        case .workStarted:
            startWork()
        case .workEnded:
            endWork(waitingForUser: await hasOpenQuestion())
        default:
            return
        }
    }

    /// Ends the lease. The drive of the child calls it when the child closed,
    /// failed or was cancelled. A second call does nothing.
    func end() {
        let lease: BackgroundWork? = phase.withLock { phase in
            defer { phase = .ended }
            switch phase {
            case .open(let lease), .suspended(let lease):
                return lease
            case .notStarted, .noWork, .ended:
                return nil
            }
        }
        lease?.end()
    }

    /// Resumes a suspended lease, or begins a new lease when no lease is
    /// open. An open lease does not change.
    private func startWork() {
        phase.withLock { phase in
            switch phase {
            case .suspended(let lease):
                lease.resume()
                phase = .open(lease)
            case .noWork:
                guard let call else { return }
                phase = .open(call.beginBackgroundWork(.childSession, id: leaseID))
            case .notStarted, .open, .ended:
                return
            }
        }
    }

    /// Suspends the open lease when the child waits only for the user, else
    /// ends it.
    ///
    /// - Parameter waitingForUser: `true` when the child has an open
    ///   question.
    private func endWork(waitingForUser: Bool) {
        phase.withLock { phase in
            guard case .open(let lease) = phase else { return }
            if waitingForUser {
                lease.suspend()
                phase = .suspended(lease)
            } else {
                lease.end()
                phase = .noWork
            }
        }
    }
}
