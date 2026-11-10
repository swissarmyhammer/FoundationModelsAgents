import Foundation
import FoundationModelsExtras
import FoundationModelsRouter
import ULID

extension RecordedChild {
    /// The key of the original `start agent` call of this child in the
    /// journal of its caller.
    var startCallKey: RunKey {
        RunKey(tool: ToolVocabulary.agentsToolName, correlationID: parentToolCallId)
    }
}

extension RecordedChild {
    /// The same child with another recorded first prompt.
    ///
    /// - Parameter prompt: The first prompt, or `nil` for a child whose prompt is not recorded.
    /// - Returns: The copy.
    func withFirstPrompt(_ prompt: String?) -> RecordedChild {
        RecordedChild(
            sessionID: sessionID, agentID: agentID, agentName: agentName, parentSessionId: parentSessionId,
            parentToolCallId: parentToolCallId, ended: ended, firstPrompt: prompt)
    }
}

/// The selection rule of the restore.
public enum AgentRunRestore {
    /// Selects the children that the host restores: each child with no ended
    /// marker.
    ///
    /// The ended marker is the one truth. A run marks its session as ended
    /// strictly before its final result goes anywhere (the journal of the
    /// caller, the mail to the caller), and only for a real end: finished,
    /// failed, or cancelled by a user. A child with no marker was thus cut by
    /// a shutdown or a crash, whatever the journal of its caller says.
    ///
    /// - Parameter children: The recorded children of the caller
    ///   (`RouterSessionDirectory.recordedChildren(of:)`).
    /// - Returns: The children with no ended marker, in the order of
    ///   `children`.
    public static func select(children: [RecordedChild]) -> [RecordedChild] {
        children.filter { $0.ended == nil }
    }

    /// Gives the keys of the calls that a restored caller claims in its
    /// journal: the call of each child that is an orphan there. A claimed call
    /// gets no lost event, and the restored child completes it
    /// (``AgentRunner/restore(_:prompt:deferStart:claiming:caller:)``).
    ///
    /// A child whose call is not an orphan (the journal has a terminal event
    /// for it) is not claimable. The host restores such a child anyway, and
    /// its result goes to the caller as mail.
    ///
    /// - Parameters:
    ///   - children: The children to restore.
    ///   - statuses: The run statuses of the caller
    ///     (`RouterSessionDirectory.runStatuses(of:)`). A child with no status
    ///     has no event in the journal, thus its call is claimable too. When the
    ///     read failed, the host must not call this: it claims nothing.
    /// - Returns: The keys to pass as `claiming`.
    public static func claims(for children: [RecordedChild], statuses: [RunKey: RunStatus]) -> Set<RunKey> {
        Set(
            children.map(\.startCallKey).filter { key in
                guard let status = statuses[key] else { return true }
                return status == .orphaned
            })
    }
}

/// An error of ``AgentRunner/restore(_:prompt:deferStart:claiming:caller:)``. The
/// restore starts no run.
public enum AgentRunRestoreError: Error, Sendable, Equatable {
    /// The host called ``AgentRunner/stop()``.
    case stopped

    /// The host did not call `AgentRegistry.load()` or `reload()` before the
    /// restore.
    case catalogNotLoaded

    /// The catalog has no agent with the agent id of the child.
    case unknownAgent(String)

    /// The depth of the child is more than ``AgentEnvironment/maxDepth``.
    case tooDeep(depth: Int, maxDepth: Int)

    /// The shared setup of the run failed (the instructions or the tools).
    case setupFailed(String)

    /// The Router could not restore the session.
    case sessionRestoreFailed(String)

    /// The environment has no mark closure (``AgentEnvironment/withSessionEnding(_:)``). A
    /// restored run must mark its session as ended at its real end, else the host restores
    /// it again.
    case sessionEndingMissing

    /// The `caller` run that the host gave is not the run of the caller session of the child.
    case callerMismatch
}

extension AgentRunRestoreError {
    /// `true` for an error that can pass: the host can restore the child later, thus its claim
    /// stays open. The other errors are permanent.
    public var isTransient: Bool {
        switch self {
        case .stopped, .sessionEndingMissing, .catalogNotLoaded: true
        case .unknownAgent, .tooDeep, .setupFailed, .sessionRestoreFailed, .callerMismatch: false
        }
    }
}
