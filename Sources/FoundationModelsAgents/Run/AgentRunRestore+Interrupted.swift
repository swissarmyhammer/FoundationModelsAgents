import Foundation
import Logging
import FoundationModelsRouter
import ULID

/// A recorded child that the restore did not bring back.
public struct FailedChild: Sendable, Equatable {
    /// Why the child was not restored.
    public enum Cause: Sendable, Equatable {
        /// The restore of the child was tried and failed, with a short text of the error.
        case failed(reason: String)

        /// The child was not tried, because an ancestor of it was not restored.
        case ancestorNotRestored
    }

    /// The reason text of a child whose task prompt was not recorded and that the host gave no
    /// prompt for.
    public static let promptNotRecordedReason = "its task prompt was not recorded"

    /// The reason text of an unrestored descendant of a failed child.
    public static let ancestorReason = "an ancestor was not restored"

    /// The recorded child.
    public let child: RecordedChild

    /// Why the child was not restored.
    public let cause: Cause

    /// A short text that tells why the child was not restored.
    public var reason: String {
        switch cause {
        case .failed(let reason): reason
        case .ancestorNotRestored: Self.ancestorReason
        }
    }

    /// `true` when the child was not tried, because an ancestor of it was not restored.
    public var isDescendantOfFailed: Bool {
        cause == .ancestorNotRestored
    }
}

/// The result of ``AgentRunner/restoreInterrupted(of:caller:directory:)``.
public struct RestoreReport: Sendable {
    /// The restored runs, not started, in tree order: each run comes before its children.
    public let restored: [AgentRun]

    /// The children that were not restored, in tree order.
    public let failed: [FailedChild]

    /// The sessions whose children could not be read, with a short reason. The restore went on
    /// without those children.
    public let unreadable: [ULID: String]

    /// The restored runs in the order that ``resumeAll()`` starts them: the children first, and
    /// each caller after its children.
    var resumeOrder: [AgentRun] {
        restored.reversed()
    }

    /// Starts every restored run, the children first and the callers last. Call it after the
    /// answer to the resume request of the host client.
    public func resumeAll() {
        for run in resumeOrder {
            run.resume()
        }
    }
}

/// The three reads of the restore. The public calls use a ``RouterSessionDirectory``; a test
/// can replace one read.
struct RestoreSource: Sendable {
    /// The recorded children of a session.
    var recordedChildren: @Sendable (ULID) async throws -> [RecordedChild]

    /// The statuses of the calls in the journal of a session.
    var runStatuses: @Sendable (ULID) async throws -> [RunKey: RunStatus]

    /// The recorded first prompt of a session.
    var firstPrompt: @Sendable (ULID) async throws -> String?

    /// Makes the source over a directory.
    ///
    /// - Parameter directory: The directory of the recordings.
    init(directory: RouterSessionDirectory) {
        recordedChildren = { try await directory.recordedChildren(of: $0) }
        runStatuses = { try await directory.runStatuses(of: $0) }
        firstPrompt = { try await directory.firstPrompt(of: $0) }
    }
}

extension AgentRunner {
    /// Gives the keys that the host passes as `claimingRuns` when it restores its own session
    /// `callerSession`: the original `start agent` calls of its interrupted children that are
    /// orphans in its journal. Call it before the restore of the session.
    ///
    /// - Parameters:
    ///   - callerSession: The session that the host restores.
    ///   - directory: The directory of the recordings.
    /// - Returns: The keys. It is empty when the children or the journal cannot be read.
    public func claims(
        of callerSession: ULID, directory: RouterSessionDirectory
    ) async -> Set<RunKey> {
        await claims(of: callerSession, source: RestoreSource(directory: directory))
    }

    /// The claims of `callerSession` over any source of the reads.
    func claims(of callerSession: ULID, source: RestoreSource) async -> Set<RunKey> {
        let children: [RecordedChild]
        do {
            children = try await source.recordedChildren(callerSession)
        } catch {
            logClaimReadFailure(of: callerSession, error: error)
            return []
        }
        return await readClaims(of: callerSession, children: AgentRunRestore.select(children: children), source: source)
            .claims
    }

    /// Restores every interrupted child of the session `callerSession`, and the interrupted
    /// children of each restored child, all not started. This is the whole host order in one
    /// call:
    ///
    /// 1. Read the recorded children of the caller, and select those with no ended marker.
    /// 2. For each child, read its own children and the status of their calls, and compute the
    ///    claims. A failed read gives no claims and does not stop the restore.
    /// 3. Restore the child with `deferStart`, with its claims, as a child of its caller run.
    ///    Then do the same for its children.
    /// 4. A child that cannot be restored is in ``RestoreReport/failed``, and its claim on the
    ///    live caller ends as lost. Each unrestored descendant of it is in the list too.
    ///
    /// The runs are not started. The host calls ``RestoreReport/resumeAll()`` after it answered
    /// its own client. A child that the runner holds already is skipped, thus a second call for
    /// the same caller restores nothing.
    ///
    /// - Parameters:
    ///   - callerSession: The session whose children are restored.
    ///   - caller: The run of that session when it is an agent run of this runner, else `nil`
    ///     for a session of the host.
    ///   - directory: The directory of the recordings.
    ///   - prompts: A task prompt for a child, by its session id, for a host that knows it. A
    ///     child with no recorded first prompt and no entry here is not restored: it is in
    ///     ``RestoreReport/failed``, and its claim ends as lost.
    /// - Returns: The report. The call never throws: a read that fails goes in
    ///   ``RestoreReport/unreadable``, and the host goes on with the resume of its own session.
    public func restoreInterrupted(
        of callerSession: ULID, caller: AgentRun?, directory: RouterSessionDirectory,
        prompts: [ULID: String] = [:]
    ) async -> RestoreReport {
        await restoreInterrupted(
            of: callerSession, caller: caller, source: RestoreSource(directory: directory), prompts: prompts)
    }

    /// The work of ``restoreInterrupted(of:caller:directory:)`` over any source of the reads.
    func restoreInterrupted(
        of callerSession: ULID, caller: AgentRun?, source: RestoreSource, prompts: [ULID: String] = [:]
    ) async -> RestoreReport {
        var report = Builder()
        let children = await selectedChildren(of: callerSession, source: source, report: &report)
        await restore(
            children, of: callerSession, callerRun: caller, source: source, prompts: prompts, report: &report)
        return RestoreReport(restored: report.restored, failed: report.failed, unreadable: report.unreadable)
    }

    /// Reads the statuses of the calls in the journal of `session` and computes the claims for
    /// `children`. A failed read gives no claims and the text of the error.
    private func readClaims(
        of session: ULID, children: [RecordedChild], source: RestoreSource
    ) async -> (claims: Set<RunKey>, readError: String?) {
        let read = await readStatuses(of: session, source: source)
        guard read.readError == nil else { return ([], read.readError) }
        return (AgentRunRestore.claims(for: children, statuses: read.statuses), nil)
    }

    /// Reads the statuses of the calls in the journal of `session`. A failed read is logged and
    /// gives no statuses and the text of the error.
    private func readStatuses(
        of session: ULID, source: RestoreSource
    ) async -> (statuses: [RunKey: RunStatus], readError: String?) {
        do {
            return (try await source.runStatuses(session), nil)
        } catch {
            logClaimReadFailure(of: session, error: error)
            return ([:], String(describing: error))
        }
    }

    /// Writes the record of a read that failed. The restore claims nothing for that session.
    private func logClaimReadFailure(of session: ULID, error: any Error) {
        var metadata: Logger.Metadata = [
            AgentsTelemetry.LogMetadataKey.callerSessionID: .string(session.description),
            AgentsTelemetry.LogMetadataKey.errorType: .string(String(describing: type(of: error))),
        ]
        metadata["error"] = .string(String(describing: error))
        environment.makeRunLogger().warning("\(AgentsTelemetry.LogMessage.claimReadFailed)", metadata: metadata)
    }

    /// The lists that the restore builds.
    private struct Builder {
        var restored: [AgentRun] = []
        var failed: [FailedChild] = []
        var unreadable: [ULID: String] = [:]
    }

    /// Restores `children`, the selected children of `session`, and their descendants.
    private func restore(
        _ children: [RecordedChild], of session: ULID, callerRun: AgentRun?, source: RestoreSource,
        prompts: [ULID: String], report: inout Builder
    ) async {
        // The statuses of the calls of `session`. A failed read is logged and listed as unreadable.
        // The restore goes on with no statuses: the ended marker is the truth for "restorable",
        // and the set of the sessions ended by an earlier restore still keeps a completed child
        // from a second restore.
        let read = await readStatuses(of: session, source: source)
        if let readError = read.readError {
            report.unreadable[session] = readError
        }
        let statuses = read.statuses
        for child in children {
            if sessionsEndedByRestore.contains(child.sessionID) { continue }
            if case .completed(let outcome)? = statuses[child.startCallKey], run(id: child.sessionID) == nil {
                // The call has a result, but the session has no ended marker. A restore would run
                // the work again, thus the session is marked ended and not restored.
                await endSessionOfCompletedCall(child, outcome: outcome)
                continue
            }
            let grand = await selectedChildren(of: child.sessionID, source: source, report: &report)
            if let held = run(id: child.sessionID) {
                // A second call: the run is live already. Its own children are checked below it.
                await restore(grand, of: child.sessionID, callerRun: held, source: source, prompts: prompts, report: &report)
                continue
            }
            let read = await readClaims(of: child.sessionID, children: grand, source: source)
            if let readError = read.readError {
                report.unreadable[child.sessionID] = readError
            }
            let claims = read.claims
            let prompt = prompts[child.sessionID]
            if prompt == nil, child.firstPrompt == nil {
                // Restoring blind would run the agent with no task. The claim ends as lost, thus
                // the model of the caller sees the loss and decides.
                await endClaimAsLost(of: child)
                await recordFailure(
                    of: child, reason: FailedChild.promptNotRecordedReason, children: grand, source: source,
                    report: &report)
                continue
            }
            do {
                let restored = try await restore(
                    child, prompt: prompt, deferStart: true, claiming: claims, caller: callerRun)
                report.restored.append(restored)
                await restore(grand, of: child.sessionID, callerRun: restored, source: source, prompts: prompts, report: &report)
            } catch {
                await recordFailure(
                    of: child, reason: String(describing: error), children: grand, source: source, report: &report)
            }
        }
    }

    /// Marks the session of a child ended when its call has a result in the journal of its caller.
    /// A mark that fails is logged, and the runner remembers the session, thus a later call does
    /// not restore it.
    private func endSessionOfCompletedCall(_ child: RecordedChild, outcome: OperationOutcome) async {
        sessionsEndedByRestore.insert(child.sessionID)
        let reason: SessionEndReason
        switch outcome {
        case .succeeded: reason = .finished
        case .failed, .timedOut, .other: reason = .failed
        case .cancelled, .stopped, .lost: reason = .cancelled
        }
        let metadata: Logger.Metadata = [
            AgentsTelemetry.LogMetadataKey.callerSessionID: .string(child.parentSessionId.description),
            AgentsTelemetry.LogMetadataKey.sessionID: .string(child.sessionID.description),
        ]
        _ = await environment.markSessionEnded(child.sessionID, reason: reason, metadata: metadata)
    }

    /// Gives each child its recorded first prompt when the listing holds none.
    private func withFirstPrompts(_ children: [RecordedChild], source: RestoreSource) async
        -> [RecordedChild]
    {
        var result: [RecordedChild] = []
        for child in children {
            guard child.firstPrompt == nil, let prompt = try? await source.firstPrompt(child.sessionID) else {
                result.append(child)
                continue
            }
            result.append(child.withFirstPrompt(prompt))
        }
        return result
    }

    /// The selected children of `session`. A failed read gives none and goes in the report.
    private func selectedChildren(
        of session: ULID, source: RestoreSource, report: inout Builder
    ) async -> [RecordedChild] {
        do {
            return await withFirstPrompts(
                AgentRunRestore.select(children: try await source.recordedChildren(session)),
                source: source)
        } catch {
            report.unreadable[session] = String(describing: error)
            return []
        }
    }

    /// Lists a child that was not restored as failed, and each unended descendant of it.
    private func recordFailure(
        of child: RecordedChild, reason: String, children: [RecordedChild], source: RestoreSource,
        report: inout Builder
    ) async {
        report.failed.append(FailedChild(child: child, cause: .failed(reason: reason)))
        await markDescendantsFailed(of: child.sessionID, children: children, source: source, report: &report)
    }

    /// Lists each unended descendant of an unrestored child as failed.
    private func markDescendantsFailed(
        of session: ULID, children: [RecordedChild], source: RestoreSource, report: inout Builder
    ) async {
        for child in children {
            report.failed.append(
                FailedChild(child: child, cause: .ancestorNotRestored))
            let grand = await selectedChildren(of: child.sessionID, source: source, report: &report)
            await markDescendantsFailed(of: child.sessionID, children: grand, source: source, report: &report)
        }
    }
}
