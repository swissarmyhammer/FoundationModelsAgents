import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing
import ULID

/// Pins which recorded children of a caller the host restores
/// (``AgentRunRestore/select(children:)``): a child with no ended marker.
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

    @Test("a child with no ended marker is restorable whatever the journal says: orphaned")
    func orphanedIsRestorable() {
        let child = Self.child()

        #expect(AgentRunRestore.select(children: [child]) == [child])
    }

    @Test("a child with no ended marker is restorable whatever the journal says: no status")
    func noStatusIsRestorable() {
        let child = Self.child()

        #expect(AgentRunRestore.select(children: [child]) == [child])
    }

    @Test("a child with no ended marker is restorable also when its run is completed with a real outcome")
    func unendedIsRestorableAfterSuccess() {
        let child = Self.child()
        let claims = AgentRunRestore.claims(for: [child], statuses: Self.table(.completed(.succeeded)))

        #expect(AgentRunRestore.select(children: [child]) == [child])
        #expect(claims.isEmpty)
    }

    @Test("a child with an ended marker is not restorable")
    func endedIsNotRestorable() {
        let ended = SessionEndedMarker(endedAt: Date(), reason: .finished)

        #expect(AgentRunRestore.select(children: [Self.child(ended: ended)]).isEmpty)
    }

    @Test("the claims hold the key of each child whose call is an orphan in the journal")
    func claimsHoldOrphans() {
        let child = Self.child()

        let claims = AgentRunRestore.claims(for: [child], statuses: Self.table(.orphaned))

        #expect(claims == [RunKey(tool: "agents", correlationID: Self.token)])
    }

    @Test("the claims hold no key for a call that is completed with a lost outcome")
    func claimsSkipCompleted() {
        let claims = AgentRunRestore.claims(for: [Self.child()], statuses: Self.table(.completed(.lost)))

        #expect(claims.isEmpty)
    }
}
