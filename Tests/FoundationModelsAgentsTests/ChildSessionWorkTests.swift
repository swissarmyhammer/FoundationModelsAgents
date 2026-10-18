import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Synchronization
import Testing
import ULID

/// Pins the one `childSession` lease that the `start agent` call of a child
/// holds in the registry of the parent (``ChildSessionWork``).
///
/// Each test gives the follower built work events of the child in a fixed
/// order, and reads the registry of the parent after each event. The
/// registry changes in the call of the follower, thus the tests use no clock
/// and no wait.
@Suite("Child session work")
struct ChildSessionWorkTests {
    /// The parts of one test: the registry of the parent, the context of the
    /// call that starts the child, and the id of the child.
    private struct Parts {
        /// The registry of the parent session.
        let registry: WorkRegistry

        /// The context of the `start agent` call in the parent.
        let call: ToolContext

        /// The id of the child session.
        let child = ULID()

        /// Makes the registry and the context of a new parent session.
        init() {
            let parent = ULID()
            registry = WorkRegistry(sessionID: parent)
            call = ToolContext(
                sessionID: parent, runPlane: RunPlane(workRegistry: registry), sink: DroppingSink(),
                tool: ToolVocabulary.agentsToolName, op: StartAgent.opString,
                completionToken: ToolContext.makeCompletionToken(), isCancelled: { false })
        }

        /// The item of the lease of the child in the registry of the parent.
        var item: WorkItem {
            WorkItem(kind: .childSession, id: child.description, sessionID: registry.sessionID)
        }
    }

    /// A sink that drops each event.
    private struct DroppingSink: OperationEventSink {
        /// Drops the event.
        ///
        /// - Parameter event: The event.
        func post(event: OperationEvent) async {}
    }

    /// A check of open questions that tells that the child has none.
    private static let noQuestion: @Sendable () async -> Bool = { false }

    /// A check of open questions that tells that the child has one.
    private static let openQuestion: @Sendable () async -> Bool = { true }

    @Test("the start of a child begins one childSession lease of the child in the registry of the parent")
    func startBeginsTheLease() async {
        let parts = Parts()
        let work = ChildSessionWork(call: parts.call, childSessionID: parts.child)
        defer { work.end() }
        await work.observe(.workStarted, hasOpenQuestion: Self.noQuestion)
        let beforeStart = parts.registry.openWork
        work.start()
        work.start()

        #expect(beforeStart.isEmpty)
        #expect(parts.registry.openWork == [parts.item])
    }

    @Test("the parent has no work when the child has none, and work again when the child gets new work")
    func theLeaseFollowsTheWorkOfTheChild() async {
        let parts = Parts()
        let work = ChildSessionWork(call: parts.call, childSessionID: parts.child)
        work.start()
        defer { work.end() }

        await work.observe(.workStarted, hasOpenQuestion: Self.noQuestion)
        let whileWorking = parts.registry.openWork
        await work.observe(.workEnded, hasOpenQuestion: Self.noQuestion)
        let afterTheEnd = parts.registry.openWork
        let endedLease = work.lease
        await work.observe(.workStarted, hasOpenQuestion: Self.noQuestion)

        #expect(whileWorking == [parts.item])
        #expect(afterTheEnd.isEmpty)
        #expect(endedLease == nil)
        #expect(parts.registry.openWork == [parts.item])
    }

    @Test("while the child waits only for the user, the lease is suspended, and the answer resumes it")
    func aQuestionSuspendsTheLease() async throws {
        let parts = Parts()
        let work = ChildSessionWork(call: parts.call, childSessionID: parts.child)
        work.start()
        defer { work.end() }
        let lease = try #require(work.lease)

        await work.observe(.workEnded, hasOpenQuestion: Self.openQuestion)
        let whileAsking = parts.registry.openWork
        let wasSuspended = lease.isSuspended
        await work.observe(.workStarted, hasOpenQuestion: Self.noQuestion)

        #expect(whileAsking.isEmpty)
        #expect(wasSuspended)
        #expect(work.lease === lease)
        #expect(lease.isSuspended == false)
        #expect(parts.registry.openWork == [parts.item])
    }

    @Test("the end ends the lease, and a later work event of the child begins no lease")
    func theEndIsFinal() async throws {
        let parts = Parts()
        let work = ChildSessionWork(call: parts.call, childSessionID: parts.child)
        work.start()
        let lease = try #require(work.lease)

        work.end()
        work.end()
        await work.observe(.workStarted, hasOpenQuestion: Self.noQuestion)

        #expect(lease.isEnded)
        #expect(work.lease == nil)
        #expect(parts.registry.hasWork == false)
    }

    @Test("a run with no call context holds no lease")
    func noCallNoLease() async {
        let work = ChildSessionWork(call: nil, childSessionID: ULID())
        work.start()
        await work.observe(.workStarted, hasOpenQuestion: Self.noQuestion)

        #expect(work.lease == nil)
        work.end()
    }
}
