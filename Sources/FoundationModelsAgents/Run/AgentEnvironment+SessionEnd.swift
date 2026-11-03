import FoundationModelsRouter
import Logging
import ULID

extension AgentEnvironment {
    /// Marks a session ended with the host closure, and writes the record of a mark that did not
    /// happen. This is the one place that calls ``sessionEnding``, thus the run and the restore
    /// treat each error the same way.
    ///
    /// A mark that the Router refuses for a suspended session is not an error: the host
    /// suspended the session for a shutdown, and the session stays unended on purpose, so the
    /// next process restores it. The call logs it at info level.
    ///
    /// - Parameters:
    ///   - session: The session to mark.
    ///   - reason: Why the session ended.
    ///   - metadata: The metadata of the records, for example the identity of the run.
    /// - Returns: `true` when the session is marked, or when the environment has no closure.
    ///   `false` when the mark did not happen.
    func markSessionEnded(_ session: ULID, reason: SessionEndReason, metadata: Logger.Metadata) async -> Bool {
        guard let sessionEnding else { return true }
        do {
            try await sessionEnding(session, reason)
            return true
        } catch SessionEndedMarkerError.sessionSuspended {
            makeRunLogger().info("\(AgentsTelemetry.LogMessage.sessionEndMarkSuspended)", metadata: metadata)
            return false
        } catch {
            var failed = metadata
            failed[AgentsTelemetry.LogMetadataKey.errorType] = .string(String(describing: type(of: error)))
            makeRunLogger().error("\(AgentsTelemetry.LogMessage.sessionEndMarkFailed)", metadata: failed)
            return false
        }
    }
}
