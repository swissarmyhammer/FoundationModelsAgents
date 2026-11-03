---
comments:
- actor: claude-code
  id: 01m6grb4zcp4bxf2j95y9wrvdr
  text: |-
    ## Design (no code written yet)

    ### 1. API shape
    ```swift
    public struct RecordedChild: Sendable {
        public let sessionID: ULID           // the child session, kept
        public let agentID: String           // from SessionRecord.agentID
        public let parentSessionID: ULID     // from agentSpawn.parentSessionId
        public let completionToken: String   // from agentSpawn.parentToolCallId
    }
    public struct RestoredRun: Sendable {
        public let run: AgentRun             // running again
        public let report: SessionConfigurationRestorationReport // missing tools, context mismatch
    }
    extension AgentRunner {
        public func restore(_ recorded: RecordedChild, caller: AgentRun?) async throws(AgentRunRestoreError) -> RestoredRun
    }
    ```
    - `caller == nil` means the caller is a host session, not a run.
    - Depth: `caller.depth + 1`, or `hostDepth` when `caller == nil`. The record has no depth. The family link comes from `caller.family`.
    - Working directory: from the record (`recordedWorkingDirectory`). It is part of the session, not config.
    - One call restores one session. A host restores a tree by calling it from the root down (see 5).

    ### 2. The shared step with makeSession
    `makeSession` (AgentSessionMaker.swift:60-91) does: render body, skills, AGENTS.md, instructions (:63-67), slot (:68-70), tools (:71-75), then model and session (:76-90). Extract lines 63-75 into:
    ```swift
    struct ResolvedRunSetup { let instructions: String; let slot: ModelSlot; let tools: [any Tool]; let workingDirectory: URL }
    func resolveSetup(definition:, prompt:, depth:, parent inputs:, callerLink:, agentsTool:, inheritedSlot:, workingDirectory:) async throws(AgentRunFailure) -> ResolvedRunSetup
    ```
    - `makeSession` calls it, then makes a NEW session (as now).
    - `restore` calls it with the CURRENT definition and catalog, then calls the Router restore with `instructions:` and `tools:` from the result. No second copy of the tool build.
    - `$ARGUMENTS`: a restore has no prompt. The original prompt is in the transcript. Question 1 below.
    - The slot: `ModelMatch.match` over the CURRENT definition. The Router restore takes the slot from the record and has no slot parameter. A current slot that differs from the record is a typed error (`modelSlotChanged`) in the first version. Question 4 below.

    ### 3. CallerLink from a session id only
    Today `CallerLink { call: ToolContext; sessionID: ULID }` (AgentsToolContext.swift:14-22). The `call` is used in ONE place: `messageCaller` does `await callerLink.call.message(message)` (:334). That posts a `.message` event on the original `start agent` call. Other uses read only `sessionID` (:307, AgentsTool.swift:191).
    Problem found: after a restore, the caller's outbox and run plane are new, and the old run is not open. `ToolContext.message` drops a message after the terminal event (Extras ToolContext.swift:258), and the restore manufactures a `.lost` terminal event for the old run (SessionTreeRestoration.swift:498). So a message through the OLD call would be lost, also if we rebuilt a `ToolContext`.
    Proposed shape:
    ```swift
    struct CallerLink: Sendable {
        enum Route { case call(ToolContext), mail }
        let sessionID: ULID
        let route: Route
    }
    ```
    - Live start: `route = .call(context)`, as today.
    - Restored child: `route = .mail`. The message goes as session mail to the caller (`MailSender.session(self)`), the reverse of `AgentRun.deliver` (AgentRun.swift:515). The runner finds the caller: a run it holds (`run(id:)`), else a host mail closure from `AgentEnvironment` (new field, optional).
    - Caller to restored child: `AgentRun.deliver` already works on the restored `AgentRun`.
    - `agentsToolFactory` takes the `CallerLink?` as input instead of building it from `request.context` (AgentSessionMaker.swift:163-165). `mountedGrant` keeps its rule: `hasCaller` is `callerLink != nil`.
    - No backward compatibility: callers of the old `CallerLink(call:sessionID:)` init change at once.
    - After the Router claim API exists, a restored child can use `.call` again. Question 2 below.

    ### 4. Errors
    ```swift
    public enum AgentRunRestoreError: Error, Sendable, Equatable {
        case catalogNotLoaded
        case stopped
        case definitionGone(agentID: String)
        case agentForbidden(agentID: String, reason: String)
        case modelSlotUnresolved(agentID: String)
        case modelSlotChanged(recorded: ModelSlot, current: ModelSlot)
        case recordUnreadable(sessionID: ULID, underlying: String)
        case callerUnknown(ULID)
        case depthLimit(maxDepth: Int)
        case setupFailed(AgentRunFailure)
    }
    ```
    `AgentRunnerError` stays unchanged. A host maps each case to "this child is unknown" and ends the original call as lost. Router errors (`sessionNotFound`, `notARootSession`, transcript errors) map to `recordUnreadable`.

    ### 5. Restore order
    - A host restores the ROOT first, then each child, from the root down. `caller:` is the already restored run of the parent. Unknown caller gives `callerUnknown`.
    - Reason: the Family belongs to the caller run (AgentRun.swift:366), and `begin` adds the child to `request.parent.children` (AgentRun.swift:390).
    - Waiting stays children-first: a caller waits for its children as today (AgentRun+Drive.swift:124-128).
    - Risk: a restored caller runs again at once. It could end and cancel its open children (`children.cancelOpenRuns`, AgentRun+Drive.swift:124) before the host restores the children. Proposal: `restore(..., deferStart: true)` returns the run with its answers not started, and a public `resume()` starts it. The host restores the whole tree, then resumes from the leaves up or all at once. Question 3 below.
    - Limits: `maxDepth` is checked (like AgentsToolOperations.swift:188-190). `maxConcurrentAgents` is skipped; `startWithinLimit` is not used.

    ### 6. What I need from the Router cards
    | Need | Card | Used for |
    |---|---|---|
    | restored session keeps parent session id, root session id, parent call | `01M6GQ1F2GK9M1HQV1SNTTQF9Q` | identity (design 1, 3) |
    | ended marker on the record | `01M6GPT1DM4KZNTT31NMQ0962J` | skip finished children |
    | restore of ONE spawn child by id (verify `notARootSession`, SessionTreeRestoration.swift:265, passes) | none; test first | restore |
    | public lookup of recorded children by `agentSpawn.parentToolCallId` / `parentSessionId` | NOT decided | the host finds the children |
    | public orphan scan without the parent restore | NOT decided | host side |
    | write-ahead + claim API | `01M6GK7RHHHC6B6QMJ25FT1QDT`, `01M6GK8K45DRDT6B4SHB9V60ED` | complete the ORIGINAL call; `StartedRuns` entry under the OLD token; `.call` route |
    | optional: public read of the first user prompt of a recorded session | none | `$ARGUMENTS` |
    Parts (a) need no Router card: CallerLink route and the shared step. Part (b), the restore API, needs the identity card, the ended marker and the lookup.

    ### 7. Order of work
    (a) /tdd: `CallerLink.Route` + `messageCaller`, then the shared `resolveSetup`. All current tests stay green.
    (b) After the Router cards: test that a Router restore accepts a spawn child; read the real tool name in the journal; then `AgentRunRestoreError`, `RecordedChild`, `RestoredRun`, `restore`, and the tests of the card.

    ### 8. Open questions
    1. `$ARGUMENTS` of a restored body: recorded first prompt (needs a Router read), or empty? I recommend the recorded prompt if the Router gives a public read, else empty.
    2. A message from a restored child to its caller arrives as plain mail until the claim API exists. Acceptable?
    3. `deferStart` and `resume()` so that a caller does not end before its children are restored. I recommend yes.
    4. A changed model slot: typed error (my proposal), or follow the current slot?
  timestamp: 2026-11-03T13:07:28.364641+00:00
- actor: claude-code
  id: 01m6grxj6xk8mkqq9ka75ykwyr
  text: |-
    ## Part (a) done: CallerLink route and the shared step (changes in the working tree, not committed)

    ### Decisions on the design (2026-11-03)
    - API shape approved: `restore(_ RecordedChild, caller: AgentRun?) -> RestoredRun`, called from the root down, `AgentRunRestoreError`, and one shared step for `makeSession` and `restore`.
    - `$ARGUMENTS` of a restored body: the RECORDED first prompt (a restored session IS that session; an empty `$ARGUMENTS` would not match the transcript).
    - A changed model slot: FOLLOW the current slot and report the mismatch as a warning in the restore report. No throw. The error case `modelSlotChanged` is NOT built.
    - `deferStart` and `resume()` approved: a restored caller must not end before its children are restored, and the continue message goes out after the ACP resume response.
    - INTERIM, not done: a message of a restored child to its caller goes as plain session mail until the Router claim API exists. The final goal stays: the result completes the ORIGINAL `start agent` call. Until then the original call stays `lost` and the result arrives as run mail. The restored run keeps the old completion token (`RecordedChild.completionToken`) so that the later completion is possible.

    ### Built in part (a)
    - `AgentsToolContext.CallerLink` is now `{ sessionID, route }` with `Route = .call(ToolContext) | .mail`. `messageCaller(_:from:)` posts to the call on `.call` and sends mail on `.mail`; the one reader of the old `call` field is changed. A mail that cannot go out gives the corrective `AgentsToolText.callerNotReachable` and the `not_delivered` telemetry outcome.
    - `AgentRunner.mailCaller(_:from:to:)`: a caller that is a run of the runner gets the message through `AgentRun.deliver(_:from: .session(sender))`; any other caller (a host session) gets it through the new `AgentEnvironment.callerMail` closure (parameter of `AgentEnvironment.make` and the init, default `nil`).
    - `AgentRunRequest.restoredCaller` and `AgentRunRequest.callerLink`: a request with a restored caller gives the `.mail` link; a live start still gives the `.call` link.
    - `AgentSessionMaker.resolveSetup(for:family:)` returns `ResolvedSetup { instructions, slot, tools, workingDirectory }`. `makeSession` calls it. No second copy of the tool build exists. `mountedGrant` is unchanged: a restored child counts as a run with a caller, so it gets the messaging tool.
    - No backward compatibility: the old `CallerLink(call:sessionID:)` is removed; one test is changed to the new shape.

    ### Tests
    - New `CallerMailRouteTests` (7) and `ResolvedSetupTests` (5), written first and seen to fail for the missing API.
    - Full suite: 693 tests in 96 suites pass.

    ### Environment note
    - `Package.resolved` is not tracked. The pinned Extras revision did not have `ChangedIDs`/`ToolkitID`, and the Extras `main` needed a newer `mlx-swift-lm`, so `main` did not build. I ran `swift package update` once (Extras `c922cca`, Router `fde4132`, mlx-swift-lm `20a9984`). No tracked file changed by this.

    ### Left for part (b), after the Router cards
    `AgentRunRestoreError`, `RecordedChild`, `RestoredRun`, `restore`, `deferStart`/`resume()`, the recorded first prompt for `$ARGUMENTS`, the model slot warning in the report, the `StartedRuns` entry under the old token (later), and the tests of the card.
  timestamp: 2026-11-03T13:17:31.741699+00:00
- actor: claude-code
  id: 01m6h09hj2hcwjf9jpkbc5pqm1
  text: |-
    Part (b) design, against the Router names that are on the way. The Router checkout does not have them yet, so no code and no test is written yet.

    Router facts that this design uses:
    - AgentSpawn stores rootSessionId. If a host builds an AgentSpawn with no parentCall and no root, the Router sets the root to the PARENT. This is wrong for a grandchild.
    - A restore re-applies agentSpawn and builds the MountSite from the record. A ToolContext cannot be built from ids.
    - A restored child is the root of its own run plane. Its root user presence is its own presence.
    - The question relay target comes only from a live parent. A restored child with no live parent has none.

    Use of the Router names:
    1. Find: recordedChildren(of: caller) gives the RecordedChild values. unendedChildren(of:) and endMarker(of:) show which ones have no ended marker. runStatuses(of:) gives .orphaned or .completed for each RunKey. The restore API accepts only a child that is unended AND .orphaned. Other children give AgentRunRestoreError.
    2. Restore: session(id:) gives the record. The restore passes the recorded rootSessionId (or the parentCall) explicitly. It never lets the Router default the root. The normal start path keeps passing the parentCall.
    3. Tools: resolveSetup builds the tools from the current catalog. The tools of a restored child use a MountSite, not a ToolContext. The caller link has the mail route, which already covers the caller. A tool that needs a ToolContext gets none; the first test lists such tools.
    4. Questions: a restored child with a non-live parent has no question target. Its run uses its own user presence.
    5. Ended marker: AgentRun calls markEnded when the run reaches a terminal state (finished, failed, cancelled), BEFORE the final result goes to the caller. The place is AgentRun.end(in:). A restored run also calls it. If markEnded throws, the run records the error in telemetry and still posts the result.

    Tests (first version, with a stub of the Router lookup until the names land):
    - A run that reaches finished, failed or cancelled calls markEnded once, before the result is posted.
    - A restore reads the recorded rootSessionId, not the parent.
    - A restore of an ended child gives AgentRunRestoreError.
    - A restore of a .completed run gives AgentRunRestoreError.
  timestamp: 2026-11-03T15:26:24.322294+00:00
- actor: claude-code
  id: 01m6h09wrkeqqwz3nvq8mjs3pq
  text: |-
    Design approved by the coordinator, with two corrections.

    Correction to point 1 (which children to restore): restore a child that is UNENDED and NOT completed with a real outcome. This holds three cases:
    - an orphaned run;
    - a run with NO status at all (the child stopped before its first journal event; only the recorded-child listing finds it);
    - a run with status .completed and the outcome LOST. This is the orderly shutdown: the Router run plane sweep on close() posts a lost terminal event for each working run, so after a normal quit the working runs look completed(lost). The user wants these runs to work again.
    A run completed with finished, failed, or cancelled by its caller is NOT restored.

    Correction to point 5 (markEnded): call it only when a run reaches a REAL terminal state (finished, failed, or cancelled by its caller), before the final result is posted. runner.stop() at process shutdown, and any cancel that the shutdown causes, must NOT mark the run ended. If they did, those runs could not be restored.

    Added tests:
    - A shutdown (runner.stop()) leaves the run unended.
    - A normal finish marks the run ended.
    - A cancel by the caller marks the run ended.
    - A restore of a child with no status is accepted.
    - A restore of a completed(lost) child is accepted.
    - A restore of a child completed with finished is refused.

    No code is written. I wait for the Router push before I write code against the new names.
  timestamp: 2026-11-03T15:26:35.795291+00:00
- actor: claude-code
  id: 01m6h2sz7dsdad7rzcg0ge4363
  text: |-
    Part (b) is in the working tree, with the real Router names (Router 2306ebb4).

    Built:
    - AgentEnvironment.sessionEnding (closure) and withSessionEnding(_:). AgentRun marks its session as ended on finished, failed, or a cancel by the caller, before the result is given. AgentRunner.stop() and cancelRuns(caller:) use cancelForShutdown(), so they never mark. Tests: RunEndedMarkTests (3).
    - AgentRunRestore.select(children:statuses:) and RestoreCandidate. It restores a child that is unended and not completed with a real outcome (orphaned, no status, completed-lost). A failed status read gives .unknown for each unended child. Tests: RestoreSelectionTests (6).
    - AgentRunner.restore(_:prompt:) and AgentRunRestoreError. It uses resolveSetup, so tools and instructions come from the current config. The caller link has the mail route. It skips maxConcurrentAgents and checks maxDepth. The first message is AgentsToolText.restoredRunContinue. Tests: RestoreRunTests (5), with a real Router restore of a stopped run.
    - NestedRunTests now expects the true rootSessionId. This proves the normal start path passes the parentCall root.

    Not built yet:
    - The recorded first prompt for $ARGUMENTS. The Router has no public read of it, so the host passes prompt, and the default is empty.
    - The slot-mismatch warning, and the StartedRuns entry under the old token (waits for the Router claim API).
    - The depth of a restored child is the depth of its held caller run plus one, else two.

    TDD note: I wrote AgentRunRestore.select and AgentRunner.restore before their tests, and then the tests passed at once. I did not see RED for those two.
  timestamp: 2026-11-03T16:10:19.757020+00:00
- actor: claude-code
  id: 01m6h3087xvvq95wfxtjv1tm3d
  text: |-
    Mutation check of the part (b) tests. I broke each rule on purpose, ran its tests, saw a failure, and restored the code.

    | Rule | Mutation | Test that failed |
    |---|---|---|
    | select: completed-lost is restorable | any completed run is excluded | "a child whose run is completed with a lost outcome is restorable" |
    | select: no status is restorable | a child with no status is dropped | "a child with no status at all is restorable" |
    | select: a real outcome is not restorable | no completed run is excluded | "a child whose run is completed with a real outcome is not restorable" |
    | restore: the recorded root, not the Router default | the session maker passes no parentCall | NestedRunTests "agentSpawn links three sessions ..." |
    | markEnded: never on shutdown | a shutdown cancel marks the session | RunEndedMarkTests "a stop of the runner leaves the session of a working run unended" |

    Review (6 findings) fixed: one CancelReason enum (none, shutdown, caller) in place of two Bools; a failed mark is logged with the error type only, and the result stays; startableDefinition(named:) and withSetup(caller:_:) shared by start and restore; the mail-route test asserts the route; one generic CallRecord in Support replaces four recorder copies.

    First prompt: the Router has no public read of the first prompt. The interim: the host passes `prompt`, and the default is empty. When RecordedChild gets `firstPrompt`, restore uses it as the default.

    Claim API (waits for the Router): when it lands, restore will call the claim for the OLD completion token, which is `child.parentToolCallId` and the correlation id of the run in the journal of the caller. The result of the restored run then completes the ORIGINAL `start agent` call, and the runner adds a StartedRuns entry under that token. The exact claim name is not known yet.
  timestamp: 2026-11-03T16:13:45.597586+00:00
- actor: claude-code
  id: 01m6h38qrv2sezhkzxcvp2svjj
  text: |-
    Answers to the three risks of the coordinator.

    CORRECTION of an earlier claim: a restored child did NOT mail its final result to its caller. A restored run has no live `start agent` call, so nobody posted its result. This is fixed now: a restored run mails its final report to its caller when it ends (AgentRunRequest.resultMail, through AgentRunner.mailCaller). The mail goes after the ended mark.

    1. A restored caller must not end before its restored children are attached.
    - `restore(_:prompt:deferStart:)` has `deferStart`, and `AgentRun.resume()` starts the run. A deferred run has its session and its place in the family of its caller, and it gets no message until `resume()`.
    - A restored child adds itself to the family of its caller at restore time, when the runner holds the caller run (AgentRun.parentRun). A run waits for its children only through this family.
    - Host order: restore the caller with deferStart, restore its children (deferStart too), restore their children, then resume() from the leaves up to the caller. Without deferStart the order is caller first, children after, and the caller can end before its children attach.
    - A cancel of a deferred run (runner.stop(), cancel()) closes its session and ends it as cancelled.
    - Test (RestoreChainTests): a caller, a child and a grandchild. The caller gives the result that holds the grandchild result. Mutation: if the hold is ignored, the test fails ("result.contains(grandchildText)").
    - The depth rule applies: a chain of three below a host session needs maxDepth 4.

    2. Timing. `restore` does no work before it is called. The runner reads nothing at init, and the host calls restore after the ACP resume response. Each call restores one child, and it is safe to call once per child. A second call for the same session finds the session live and the Router refuses it (sessionRestoreFailed).

    3. HARD PRECONDITION for the host: the host integration (cold resume and the re-drive of interrupted children in the agent package) stays OFF until the Router claim API and the write-ahead record land. Until then the Router restore posts a lost event for each orphan run to the caller, the caller model may start a NEW agent for the same work, and the host also restores the old child: duplicate work. The restore API stays as built.

    Host usage note:
    1. For each caller session, from the root down: `recordedChildren(of:)` and `runStatuses(of:)`. Put an error of the status read into `.failure`.
    2. `AgentRunRestore.select(children:statuses:)`.
    3. Restore each `.restorable` child with `restore(_:prompt:deferStart: true)`, caller first, then its children. Then `resume()` from the leaves up.
    4. Announce each `.unknown` child as unknown.
    5. Give the environment `callerMail` for a caller that is not a run, and `withSessionEnding { try await directory.markEnded($0, reason: $1) }`.
  timestamp: 2026-11-03T16:18:23.643396+00:00
- actor: claude-code
  id: 01m6h59s5s0v9fm0eyhvs43qpm
  text: |-
    Shutdown order test, option A, with the real Router and a scripted model. Chain: root host session, caller, middle, leaf. The leaf waits on a gate.

    Result: option A does NOT work with the current code. Order tested: root.close() first, then runner.stop(). The journal of the root holds the start-agent call of the caller as completed(succeeded), text "Agent ... was cancelled." It is not completed(lost). Thus select() does not find the run, and the run is not restorable. The same result holds for runner.stop() first and for the call that is still background (the caller waits for its children).

    Cause: the Router cancels the body of the start-agent call when the session closes. Our cancel handler cancels the run, the run reports "cancelled", the body returns that text, and the Router records any returned body as succeeded. This happens before the close sweep can post a lost event.

    What I tried and removed: the body throws CancellationError (still succeeded); the body parks (session close hangs). Nothing of this is committed.

    Not tested: runner.stop() after close() on a run whose session is closed (no hang seen in the test run; the test finished). The mark: a body cancel is treated as a cancel of the caller, so the run marks its session ended as cancelled. This is also wrong for a shutdown. Fix in Agents (small, safe): the cancel of the body (session close) should use cancelForShutdown. It does not fix the journal outcome.

    The WIP end-to-end test is at /private/tmp/claude-501/wip/RestoreEndToEndTests.swift and in the working tree, not committed (its cases fail). The Router session is asked how a body must end to leave the call open or lost.
  timestamp: 2026-11-03T16:53:55.001510+00:00
- actor: claude-code
  id: 01m6h5yds19mdsxf2f3s5nsq95
  text: |-
    Coordinator decisions built (Router b24f6c62 claim API).

    1. select: a child is restorable if it has no ended marker, whatever the journal says. API: `AgentRunRestore.select(children:)`. The `.unknown` candidate and the statuses parameter are removed. Tests: unended is restorable, ended is not.

    2. Claims: `AgentRunRestore.claims(for:statuses:)` gives the keys of the children whose call is an orphan. The host passes them as `claiming` when it restores the caller. `restore(_:prompt:deferStart:claiming:)` passes them to restoreSession. A key that is not an orphan makes the restore fail before any session restores (test: runNotClaimable). A child whose call is not claimable is restored anyway, and its result comes to its caller as mail (interim path).

    3. When a restored child ends, it completes the original call with `completeClaimedRun` (outcome succeeded, failed or cancelled; the report as detail) on the live caller session, then mails the report to the caller. The mail wakes the caller. If a child cannot be restored, its claim ends as lost on the live caller session. NOT tested end to end: a real orphan needs a crash without the close sweep, which the Router suspending close will give. The code path for completeClaimedRun is only compiled and covered by the not-claimable test.

    4. Order and failure of the mark: in AgentRun the mark (sessionEnding) completes before the result mail and before the state that releases the journal result. If the mark fails, the run logs the error type, posts no result mail, and stays restorable. Tests: mark before mail; failed mark mails nothing.

    5. Shutdown: `runner.stop()` marks nothing and posts no result mail, also for a run that finished after the stop (a cascade). `cancelRuns(caller:)` is for a user-closed session and marks the runs as cancelled. Tests for both. Mutation checks: failed mark still mails, shutdown still mails, shutdown still marks, mail before mark: each made a test fail.

    6. `AgentRun.completionToken` is public: the token of the live call, or the old token of a restored run. `check agent` and `cancel agent` find a restored run by the old token (runner.run(completionToken:)).

    7. Open: the journal result of a LIVE `start agent` call at a runner stop still records succeeded (the Router records any returned body as succeeded). With the unended-marker rule this does not matter for select. The Router suspending close is not in my checkout yet.

    Docs: RunningAnAgent.md has the sections "Restoring an interrupted run" and "The ended marker".
  timestamp: 2026-11-03T17:05:11.457056+00:00
position_column: review
position_ordinal: '8180'
title: AgentRunner restores an interrupted child run from disk and continues it, with tools and instructions from the current config
---
## What
Give a host a way to restore an INTERRUPTED sub-agent run from disk and drive it to its end. The host is FoundationModelsACPAgent: on a cold `session/resume` it must get back the sub-agents that were still working when the process stopped.

BLOCKED BY (Router board):
- Router card `01M6GQ1F2GK9M1HQV1SNTTQF9Q`, "A restored sub-agent session keeps its identity: parent session id, root session id and parent call". It gives the identity of a restored child.
- Router card `01M6GPT1DM4KZNTT31NMQ0962J` (ended marker).
The two Router cards for the completion of the original call (below) block only the last part of the design.

USER DECISIONS (2026-11-03):
- A run that is DONE has nothing to restore. Only runs that were still working (interrupted) are restored. The host marks the record of a child as ended when its run reaches a terminal state (Router card `01M6GPT1DM4KZNTT31NMQ0962J`). A restore skips each ended record.
- Runs stay ONE-SHOT. `AgentRunState` has no idle state (running, then finished, failed or cancelled once). A restored run goes on from where the transcript stopped: restore and continue in one call. It ends once, and its result completes the ORIGINAL `start agent` call of the caller (that part needs the two Router cards, see below).
- A restored session IS that session, not another. The own session id, the parent session id, the root session id and the parent call identity of a restored child are the same as before the stop. The actual tools can change; the sessions are the sessions. The restore does not skip this in the first version.
- A restored child keeps its tool to message its caller. `CallerLink` changes so that it can come from a restored caller with its session id only, with no live `ToolContext` of the original call. The caller can message the restored child too.
- In the FIRST version, only the tools and the instructions of a restored run come from the CURRENT config. The compaction budget, the compaction prompt, the settle grace and `mailOnlyAnswerLimit` come from the RECORDING (configuration, not identity). The recording holds tool names only to report a mismatch.
- Every session is the same kind of thing. A chain of root, child and grandchild follows one rule at each level. Depth is not a case in the criteria or the tests.

## Facts (read in the code)
- A child session is made in `AgentSessionMaker.makeSession(for:family:)` (`Sources/FoundationModelsAgents/Run/AgentSessionMaker.swift:60`): body and skills, AGENTS.md files, model slot (`ModelMatch`), compaction budget, tools. The tools come from `definition.tools` and `definition.disallowedTools` over `environment.tools`, plus an `agents` tool made for this run (`tools(for:as:)`, private, :124; `agentsToolFactory`, :159; `mountedGrant`, :198).
- `AgentSessionMaker.agentsToolFactory` builds `CallerLink(call:, sessionID:)` from a live `ToolContext` (`AgentSessionMaker.swift:163-165`). `mountedGrant` gives the messaging grant only when the run has a caller (:198-205).
- `AgentRun.id` is the session id (`AgentRun.swift:376`). `AgentRun.caller` is the session id of the caller.
- A run closes its session when it ends (`AgentRun+Drive.swift:129`; `AgentRun.end` sets `session = nil`). A close does NOT delete the recording. The ended marker (Router card above) tells a finished child from an interrupted child on disk.
- `StartedRuns` is in memory, keyed by completion token (`Tool/StartedRuns.swift:36,89`). A crash loses it.
- `maxRetainedRuns` limits the finished records (`AgentRunner.swift:398-407`).
- The caller owns the `Family` (`ParentRun.Family`, `AgentRun+Children.swift:50`). A run makes its Family in `AgentRun.make` (`AgentRun.swift:366`). A child needs `request.parent` before `begin` (`AgentRun.swift:389-396`).
- `AgentRunRequest.agentSpawn` stores `parentSessionId` = session of the caller and `parentToolCallId` = the COMPLETION TOKEN of the call, not the SDK tool call id (`AgentRunRequest.swift:85-90`).
- A Router restore takes no `parentCall` (`SessionRestoration.swift:154-173`), and `agentSpawn` is not re-applied (`SessionTreeRestoration.swift:~180`). Today a restored child does not keep its parent call identity. The Router identity card closes this.

## How a host finds the child of an orphan run (verified by reading)
Chain: orphan `RunKey(tool, correlationID)` of the parent session, where `correlationID` is the completion token (`Router SessionEvent.swift:40,83,93,226`; `SessionTreeRestoration.swift:693-697, 746-767`) EQUALS the recorded child with `agentSpawn.parentToolCallId` == that token and `agentSpawn.parentSessionId` == the parent session id. The SDK tool call id is NOT part of the chain. Do not use `ToolCallRunJoin`: it joins a different id and can swap ids when one tool runs twice at once.

Where the chain can still break:
1. Tool name. The `RunKey.tool` is the tool name that the Router journals. The card must read the real name in a journal (not verified).
2. A child that never journaled an event. An orphan needs a non-terminal event (`.progress`, `.elicitation`, `.message`). A child that stopped before its first event gives no orphan, but its record and spawn record exist. The host must also list recorded children by `agentSpawn.parentSessionId`.
3. Orphans exist only during the restore of the PARENT session (`SessionTreeRestoration.swift:498`, posts `.lost` events to the outbox). `lostRunTerminalEvents` is internal. No public orphan scan exists.
4. Is a spawn child a restore root? `restoreSessionTree` needs `rootNode.parentId == nil` (:265, `notARootSession`). `parentId` comes from folder nesting (forks), so a spawn child should pass. Test it.
5. No public lookup of recorded children by `agentSpawn.parentToolCallId`.

Write the result of items 1 and 4 in a task comment before the design is final.

## Design
1. API on `AgentRunner`, shape:
   `restore(_ recorded: RecordedChild, caller: AgentRun?, ...) async throws(AgentRunRestoreError) -> RestoredRun`
   `RecordedChild` holds the session id, the agent id, and the original completion token. `RestoredRun` holds the running `AgentRun` and the Router restore report (missing tools, context mismatch). The runner computes depth and family link from the caller run that it holds. Depth comes from the caller chain, never from the record (the record has no depth).
2. Shared step. Extract from `makeSession` (lines 63-75) the step "resolve instructions + slot + tools" into one function that returns a value. `makeSession` and `restore` both call it. There is no second copy of the tool build. The model and session creation differ and stay separate.
3. Restore order. The CALLER run (owner of the Family) is restored first. Its children attach after. The wait order stays children-first: a caller run waits for its children. Order for a host: from the root down, each caller before its children.
4. Limits. Restore checks `maxDepth` (as `AgentsToolOperations.swift:188-190`). Restore skips `maxConcurrentAgents`: the work was already running before the stop, and `startWithinLimit` never queues. A restore above the depth limit gives a typed error.
5. CallerLink (DECIDED). `CallerLink` can be made from a caller session id alone, with no live `ToolContext`. A live start still gives the call as before. A restore gives the session id of the restored caller. `agentsToolFactory` and `mountedGrant` treat a restored child as a run with a caller, so that the restored child gets the messaging tool. The messaging operations of the tool (`send caller`) use the session id and need no original call. Check every place that reads `CallerLink.call` (the call is optional after the change) and keep one code path for both cases.
6. Errors. A separate type `AgentRunRestoreError` (not `AgentRunnerError`). Cases: definition gone, agent forbidden by the current config, model slot does not resolve, record unreadable, depth above limit, caller unknown. `makeSession` failures (`AgentRunFailure`) map to it.
7. The restore mails one "The process stopped. Continue your work." message. `AgentRun.begin` needs a variant that sends this message in place of `request.prompt`.
8. Identity. The restore passes what the Router identity card asks for, so that the restored child keeps its parent session id, root session id and parent call. The runner gives the Router the recorded spawn (`parentSessionId`, `parentToolCallId`) of the child. The tests check `ToolContext.parentSessionID` and `rootSessionID` in each restored session against the values before the stop.
9. Later part (needs the Router cards below): `StartedRuns` needs an entry keyed by the OLD completion token, so that the result completes the ORIGINAL `start agent` call. `add(_:forCall:)` needs a `ToolContext` today (`StartedRuns.swift:88`). A restore has none. Design this after the Router claim API exists.

## Recorded values in the first version
A Router restore takes tools, instructions, user presence, hook key, `isNoOpToolCall` and tool output protection from the caller. It takes the compaction budget, the compaction prompt and the settle grace from the RECORDING (`SessionTreeRestoration.swift:409-422`). It has no parameter for `mailOnlyAnswerLimit`.
The user decided: the first version of the restore accepts the RECORDED values for the compaction budget, the compaction prompt, the settle grace and `mailOnlyAnswerLimit`. This is configuration. Only the tools and the instructions come from the current config. No Router card for these restore parameters is written now. The restore report and the docs state this limit. The tests cover tools and instructions only for the current-config rule.

## Needs from the Router board (the user decides; do not write Router cards from this board)
1. Ended marker: DECIDED. Router card `01M6GPT1DM4KZNTT31NMQ0962J`. The host sets it when a run reaches a terminal state.
2. Identity of a restored child: DECIDED. Router card `01M6GQ1F2GK9M1HQV1SNTTQF9Q`. This card is blocked by it.
3. Public lookup of recorded children by `agentSpawn.parentToolCallId` (and by `parentSessionId`): NOT decided, no card.
4. Public orphan scan that does not need the restore of the parent: NOT decided, no card.
Existing Router cards for the completion of the original call: write-ahead `01M6GK7RHHHC6B6QMJ25FT1QDT` and claim API `01M6GK8K45DRDT6B4SHB9V60ED`. The restore and continue part can be built and tested without them (the result then arrives as run mail).

Consumer: FoundationModelsACPAgent board, tag `subagents`, tasks `01M6GJPPXWKQJ9E6SK5WD0CWZ7` (cold resume) and `01M6GK6AX0RWQ1PDT89GC0991F` (re-drive).

## Acceptance Criteria
- [ ] `AgentRunner.restore` brings back an interrupted chain of three sessions (root, child, grandchild) with one rule at each level: each session is linked to its caller and runs again.
- [ ] Each restored session keeps its session id, parent session id, root session id and parent call identity.
- [ ] A restored child can message its caller, and the caller can message the restored child. `CallerLink` comes from the session id of the restored caller, with no live `ToolContext` of the original call.
- [ ] The caller run is restored first, and its children attach to it. A caller waits for its children.
- [ ] A child whose record is marked ended is not restored (needs the ended marker of the Router card).
- [ ] The restored run has the tools and instructions of the CURRENT definition: change `disallowedTools` between the stop and the restore, and the restored run follows the new config.
- [ ] A definition that is gone, a forbidden agent, an unresolved model slot, an unreadable record, and a depth above the limit each give a distinct `AgentRunRestoreError`.
- [ ] `makeSession` and `restore` share one function for instructions, slot and tools.
- [ ] Restore checks `maxDepth` and skips `maxConcurrentAgents`.
- [ ] `AgentRunState` has no idle state.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentRunnerRestoreTests.swift`: stop a chain of three sessions (root, child, grandchild) in the middle with the stub model, and restore it with the same checks at each level; identity of each restored session; a restored child sends a message to its caller and the caller sends one to it; ended child not restored; config change of tools and instructions; each error; order; depth limit; no concurrency limit.
- [ ] A test of `CallerLink` made from a session id alone (no `ToolContext`) gives the messaging tool, and a live start still gives the same tool as before.
- [ ] Run `swift test --filter AgentRunnerRestoreTests`. All pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Design first: write the design in a task comment and discuss it with the user before the code.