import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing
import ULID

/// Pins which recorded children of a caller the host restores
/// (``AgentRunRestore/select(children:statuses:)``): a child that is not
/// ended and whose run is not completed with a real outcome.
@Suite("The selection of the children to restore")
struct RestoreSelectionTests {
    /// The completion token of the spawning call in each test.
    private static let token = "completion-token-1"

    /// Makes a recorded child.
    ///
    /// - Parameter ended: The ended marker, or `nil`.
    /// - Returns: The child.
    private static func child(ended: SessionEndedMarker? = nil) -> RecordedChild {
        RecordedChild(
            sessionID: ULID(), agentID: "code-reviewer", agentName: nil, parentSessionId: ULID(),
            parentToolCallId: token, ended: ended)
    }

    /// Makes the status table of a caller whose one run has `status`.
    ///
    /// - Parameter status: The status of the run.
    /// - Returns: The table.
    private static func table(_ status: RunStatus) -> [RunKey: RunStatus] {
        [RunKey(tool: "agents", correlationID: token): status]
    }

    @Test("a child with an orphaned run is restorable")
    func orphanedIsRestorable() {
        let child = Self.child()

        let result = AgentRunRestore.select(children: [child], statuses: .success(Self.table(.orphaned)))

        #expect(result == [.restorable(child)])
    }

    @Test("a child with no status at all is restorable")
    func noStatusIsRestorable() {
        let child = Self.child()

        let result = AgentRunRestore.select(children: [child], statuses: .success([:]))

        #expect(result == [.restorable(child)])
    }

    @Test("a child whose run is completed with a lost outcome is restorable")
    func completedLostIsRestorable() {
        let child = Self.child()

        let result = AgentRunRestore.select(children: [child], statuses: .success(Self.table(.completed(.lost))))

        #expect(result == [.restorable(child)])
    }

    @Test("a child whose run is completed with a real outcome is not restorable")
    func completedSucceededIsNotRestorable() {
        let result = AgentRunRestore.select(
            children: [Self.child()], statuses: .success(Self.table(.completed(.succeeded))))

        #expect(result.isEmpty)
    }

    @Test("a child with an ended marker is not restorable")
    func endedIsNotRestorable() {
        let ended = SessionEndedMarker(endedAt: Date(), reason: .finished)

        let result = AgentRunRestore.select(
            children: [Self.child(ended: ended)], statuses: .success(Self.table(.orphaned)))

        #expect(result.isEmpty)
    }

    @Test("a status read that failed gives each unended child as unknown, with the reason")
    func failedStatusReadGivesUnknown() {
        struct Damaged: Error, CustomStringConvertible { let description = "damaged tree" }
        let child = Self.child()

        let result = AgentRunRestore.select(children: [child], statuses: .failure(Damaged()))

        #expect(result == [.unknown(child, reason: "damaged tree")])
    }
}
