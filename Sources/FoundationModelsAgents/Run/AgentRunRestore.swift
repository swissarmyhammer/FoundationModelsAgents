import Foundation
import FoundationModelsExtras
import FoundationModelsRouter
import ULID

/// One recorded child of a caller session, as the restore sees it.
public enum RestoreCandidate: Sendable, Equatable {
    /// The child has work to restore: restore it with
    /// ``AgentRunner/restore(_:prompt:)``.
    case restorable(RecordedChild)

    /// The record of the caller is damaged, thus the state of the child is
    /// unknown. The host announces the child as unknown, and the resume of
    /// the caller goes on.
    case unknown(RecordedChild, reason: String)
}

/// The selection rule of the restore.
public enum AgentRunRestore {
    /// Selects the children that the host restores.
    ///
    /// A child is restorable when it has no ended marker and its run is not
    /// completed with a real outcome. These cases are restorable: an orphaned
    /// run, a run with no status (the child stopped before its first journal
    /// event), and a run that is completed with the outcome
    /// ``OperationOutcome/lost``. The last case is a normal quit: the sweep
    /// at the close of the run plane posts a lost outcome for each working
    /// run. A run that finished, failed, or was cancelled by its caller is
    /// not restorable.
    ///
    /// The match of the run uses the completion token of the spawning call
    /// (``RecordedChild/parentToolCallId``) as the correlation id of the
    /// run, with any tool name.
    ///
    /// - Parameters:
    ///   - children: The recorded children of the caller
    ///     (``RouterSessionDirectory/recordedChildren(of:)``).
    ///   - statuses: The run statuses of the caller
    ///     (``RouterSessionDirectory/runStatuses(of:)``), or the error of
    ///     that read.
    /// - Returns: The restorable children, and the unknown ones, in the
    ///   order of `children`.
    public static func select(
        children: [RecordedChild], statuses: Result<[RunKey: RunStatus], any Error>
    ) -> [RestoreCandidate] {
        children.compactMap { child in
            guard child.ended == nil else { return nil }
            switch statuses {
            case .failure(let error):
                return .unknown(child, reason: String(describing: error))
            case .success(let table):
                let status = table.first { $0.key.correlationID == child.parentToolCallId }?.value
                if case .completed(let outcome) = status, outcome != .lost {
                    return nil
                }
                return .restorable(child)
            }
        }
    }
}

/// An error of ``AgentRunner/restore(_:prompt:)``. The restore starts no run.
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
}
