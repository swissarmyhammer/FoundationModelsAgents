---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3exggs6dbbxedzmpmr0qbh8
  text: 'Search for a production caller of `AgentRunner.run(completionToken:)` and of `runIDsByCompletionToken`: the search covered Sources, Examples, Tests, and IntegrationTests. Result: there is no production caller. The only caller is `AgentRunnerTests.completionTokenFindsRun` (two calls). `Entry.completionToken` is used only to fill and trim that map. Other `completionToken` uses are not the index and stay: `AgentRunRequest.agentSpawn` (the sidecar lineage), `AgentRun+FinalMessage` (the correlation ID of the post), and tests that read `context.completionToken` from the Router journal. Decision: remove the method, the map, and the `Entry` wrapper (it holds only the run after the removal), update the test to find the run through `run(id:)` and `runs(caller:)`, and remove the token sentences from plan §9.2 and §9.3. The same sentence is also in the doc comment of `AgentsToolOperations` start and in `TheFinalMessage.md`; those also change, so that the documents match the code.'
  timestamp: 2026-09-26T13:12:12.838426+00:00
- actor: claude-code
  id: 01m3exqtcp3q17ahxkm4rd90w6
  text: |-
    Implementation done. Changes:
    - `AgentRunner.swift`: removed `run(completionToken:)`, `runIDsByCompletionToken`, and the private `Entry` struct. `openRuns` is now `[ULID: AgentRun]` and `records` is `[AgentRun]`. The behavior of `runs`, `run(id:)`, `runs(caller:)`, `startWithinLimit`, `cancelRuns`, and `retireEndedRuns` does not change.
    - `AgentRunnerTests.swift`: the test `completionTokenFindsRun` is now `toolStartedRunIsInIndex`. It finds the tool-started run through `run(id:)` and `runs(caller:)`, before and after the run finishes.
    - plan.md §9.2: removed the token-map sentence. §9.3 "The index": `token → run` is now `runs(caller:)`.
    - Same token-map sentence removed from the doc comment of `StartAgent.execute` (`AgentsToolOperations.swift`) and from `TheFinalMessage.md`, so that they match the code.
    TDD note: this is a removal with no new behavior. The updated test ran and passed before the removal (it guards the kept behavior), and it passed after the removal. There was no red step, because no new behavior was added.
    Process note: I changed three doc comments in the test file with `sed` in the shell by mistake; the repo rule says to use the files tool. The result is correct and lint is clean.
    Verification: `swift build -Xswiftc -warnings-as-errors` pass; `swift test -Xswiftc -warnings-as-errors` 359 tests in 49 suites pass; `swiftlint lint Sources Tests Package.swift Examples` 0 violations in 123 files; `cd IntegrationTests && swift build --build-tests` pass; `swift build --product agents-demo -Xswiftc -warnings-as-errors` pass. The SwiftPM "missing creator for mutated node ... mlx-swift_Cmlx.bundle" line is a build-system message, not a compiler warning; it is also present without this change.
  timestamp: 2026-09-26T13:16:12.054707+00:00
- actor: claude-code
  id: 01m3exqw4f1kngj1bq2q8ve55s
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsAgents/Run/AgentRunner.swift, Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift, Sources/FoundationModelsAgents/FoundationModelsAgents.docc/TheFinalMessage.md, Tests/FoundationModelsAgentsTests/AgentRunnerTests.swift, plan.md; swift test 359 tests in 49 suites pass; swiftlint 0 violations; IntegrationTests build --build-tests pass; agents-demo build pass
    - next: /review
  timestamp: 2026-09-26T13:16:13.839879+00:00
- actor: claude-code
  id: 01m3eyx6gte6sv5ygfh9chh9d1
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD; 1 finding (1 confirmed, 0 refuted) — Sources/FoundationModelsAgents/Run/AgentRunner.swift:184 (completeness/invariant-propagation)
    - next: Correct the open finding in the Review Findings section. The task stays in review.
  timestamp: 2026-09-26T13:36:36.890119+00:00
- actor: claude-code
  id: 01m3eyxy98ys0z37131g5dw9ns
  text: |-
    ### finish iteration 1 — stuck (conflict)
    - implement: changed — 5 files
    - test: green — swift test -Xswiftc -warnings-as-errors, 359 passed; swiftlint 0 (one unrelated flake of the burst test under CPU load, task ^9291ngj)
    - commit: 451b8d5
    - review: findings — Sources/FoundationModelsAgents/Run/AgentRunner.swift:184

    BLOCKER — the finding conflicts with a documented contract. A person must decide.
    - The finding says that `$0.id` (a run id) and `callerID` (a session id) are types that cannot be compared, and it tells us to use `$0.caller != callerID`.
    - Fact: `AgentRun.id` is the session id of the run. Its doc comment says "The id of the run. It is the session id". Thus `$0.id != callerID` removes the calling run itself from the count.
    - Plan §9.3 (Decision B, ^9geawdj, commit 4881fbe) says: the limit does not count the run that calls `start agent`. The test `AgentSchedulingTests+CallingRun.swift` proves this rule.
    - `$0.caller != callerID` removes the children of the calling session from the count, and it counts the calling run. This breaks Decision B and that test.
    - This commit did not change the rule. It changed only `$0.run.id` to `$0.id`, because the `Entry` wrapper was removed.
    Options: (1) drop the finding, because its premise is false; (2) keep the comparison and make the meaning explicit, for example a named property `sessionID` on `AgentRun` that the comparison uses; (3) change Decision B.
  timestamp: 2026-09-26T13:37:01.224264+00:00
- actor: claude-code
  id: 01m3fdwdbkd8nmhb7wtzyd9jr1
  text: |-
    The user chose option 2. Changes:
    - `AgentRun.swift`: new internal property `sessionID: ULID?`. It is equal to `id`, or `nil` for a run whose setup failed (that run has no session, and its `id` is a new ULID, not a session id). Thus the property is optional, not `ULID`.
    - `AgentRunner.startWithinLimit`: the count now uses `$0.sessionID != callerID`, with a comment that states Decision B (the limit does not count the calling run) and why `caller` is wrong there.
    - Search of the whole file and of the Run and Tool files: no other place compares a run `id` with a session id. `openRuns[run.id]`, `run(id:)`, and the sorts compare run ids with run ids. `runs(caller:)` and `cancelRuns` compare `caller` with a caller session id. These stay.
    - TDD: `AgentRunTests` now expects `run.sessionID == session.id` for a run with a session, and `run.sessionID == nil` for a body-render failure. RED: the build failed with "value of type 'AgentRun' has no member 'sessionID'". GREEN after the property.
    - Note: the `dump validators` file for one Swift path was 730 KB (11,729 lines). I could not read it in one pass.
  timestamp: 2026-09-26T17:58:19.763153+00:00
- actor: claude-code
  id: 01m3fdwf23b33xpyfv7b74wcxf
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsAgents/Run/AgentRun.swift, Sources/FoundationModelsAgents/Run/AgentRunner.swift, Tests/FoundationModelsAgentsTests/AgentRunTests.swift; swift build -Xswiftc -warnings-as-errors pass; swift test -Xswiftc -warnings-as-errors 359 tests in 49 suites pass; swiftlint 0 violations in 123 files; IntegrationTests swift build --build-tests pass
    - next: /review
  timestamp: 2026-09-26T17:58:21.507927+00:00
depends_on:
- 01M3A6D0PH2N6Z6BWHGJ8KGEGV
- 01M3A6DKKKADT8YYMXA9GEAWDJ
position_column: doing
position_ordinal: '80'
title: Remove the completion-token index that only tests use
---
## What
`AgentRunner.run(completionToken:)` and its token map (`Sources/FoundationModelsAgents/Run/AgentRunner.swift`) are used only by `AgentRunnerTests`. Plan §9.2 ("The runner index maps the `completionToken` of the call to the run") and §9.3 describe the index.

- Search the code for a production caller. If there is none, remove the method, the map, the two test calls in `AgentRunnerTests.swift`, and the sentences in plan §9.2 and §9.3.
- If a production caller needs it, keep it and add a test through that caller. Write the reason as a comment on this task.

## Acceptance Criteria
- [x] The token index is removed, or it has a production caller that a test covers.
- [x] Plan §9.2 and §9.3 match the code.

## Tests
- [x] Update `AgentRunnerTests.swift`.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-09-26 08:32)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 8 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/TheFinalMessage.md` — no validator matches this file
> - `plan.md` — no validator matches this file

- [x] `Sources/FoundationModelsAgents/Run/AgentRunner.swift:184` `completeness/invariant-propagation` — The change replaces the completion-token index with direct access to run properties, using `$0.caller` to identify runs by their session (lines 281, 287). However, line 184 compares `$0.id != callerID` where `$0.id` is a run ID and `callerID` is a session ID from `request.context?.sessionID` — these are incommensurable types. The pattern should use `$0.caller != callerID` to exclude runs from the same session, consistent with how the caller property is used elsewhere. Change line 184 to `let working = openRuns.values.count(where: { $0.isWorking && $0.caller != callerID })`.
  - Fix: the new property `AgentRun.sessionID` (the id of the session of the run, or `nil` when the setup failed) makes the session id explicit, and `startWithinLimit` now compares `$0.sessionID != callerID`, thus Decision B stays: the limit does not count the calling run. `$0.caller != callerID` is wrong, because it removes the children of the calling session from the count and counts the calling run, and that breaks Decision B and `AgentSchedulingTests+CallingRun.swift`.
