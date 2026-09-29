---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3n3bj8d5mddb7akgx07q4t7
  text: |-
    Research: `BackgroundToolRunner.start` (FoundationModelsExtras) calls `collectInstruction(forCompletionToken:)` and `canceler(forCompletionToken:)` of the tool before it gives the pending envelope, and only for a background call. `RunPlaneActor.start` always runs the body in a `Task`, thus the body of each background call always runs and ends. Thus the fix: `AgentsTool.canceler(forCompletionToken:)` opens the call in `StartedRuns`; `StartedRuns.add` or the end of `AgentsTool.call` closes it; `check agent` and `cancel agent` wait for an open call before they look up the run.

    RED: new `CheckAfterStartTests` (3 tests: check with token, check with no id, cancel with token, each in the pass after `start agent`). All 3 fail on the current code with the answers "No run has the id <token>. You have no runs." and "You have no runs.". The race is wide: even after `respond` returns, `runner.runs(caller:)` is empty. New scripted step `ScriptedAgentStep.toolCallWithLastToken(name:operation:)` reads the completion token from the last tool output.
  timestamp: 2026-09-28T22:49:48.557441+00:00
- actor: claude-code
  id: 01m3n3yys26tqb1jhz33cfdrmz
  text: |-
    Implementation landed (GREEN).
    - `StartedRuns`: new state `openCalls` (token -> waiting tasks). `open(call:)` records a call before its body runs. `add(_:forCall:)` ends the open call and resumes the waiters. New `close(call:)` ends a call whose body added no run, and drops its early cancel. New `waitForStart(ofCall:)` and `waitForStarts()`.
    - `AgentsTool.canceler(forCompletionToken:)` calls `open(call:)`: the Router asks for the canceler of each background call before it gives the envelope. `AgentsTool.call` closes the call of `ToolContext.current` in a `defer`, thus a corrective, a setup failure, or a payload that names no operation also ends the wait.
    - `AgentsToolContext.run(named:)` waits for the token before the lookup (`check agent` and `cancel agent` with an id). `reportsOfCallerRuns()` waits for all open calls (`check agent` with no id).
    - `checkWithNoIDListsOnlyRunsOfCaller` now calls `harness.tool.context.startedRuns.waitForStarts()` after the two `respond` calls, before it reads the runs.
    - Added a fourth test: `check agent` with the token of a `start agent` for an unknown agent gives the unknown-id corrective and does not wait for ever (this proves `close(call:)`).
    - Not changed (out of the scope of this card): `callerCannotCheckOrCancelRunOfOtherCaller`, `cancelRunsCancelsOnlyThatCaller` and `closeOfCallerCancelsOpenRun` read `runner.runs(caller:)` after the first gate arrival. The gate arrival comes from the driver, which `AgentRun.start` starts before `AgentRunner.start` puts the run in the index. Thus a very small race is still possible there. `waitForStarts()` is the tool to close it, if a person wants a card for it.
    - The five-times loop of `CheckAfterStartTests|AgentSchedulingTests` passed each time (15 tests).

    ### implement — changed
    - evidence: Sources/FoundationModelsAgents/Tool/StartedRuns.swift, Sources/FoundationModelsAgents/Tool/AgentsTool.swift, Sources/FoundationModelsAgents/Tool/AgentsToolContext.swift, Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift, Tests/FoundationModelsAgentsTests/CheckAfterStartTests.swift (new), Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift, Tests/FoundationModelsAgentsTests/Support/ScriptedAgentModel.swift, Tests/FoundationModelsAgentsTests/Support/ScriptedTranscriptText.swift; `swift test -Xswiftc -warnings-as-errors` 388 tests in 55 suites passed, 0 compiler warnings; `swiftlint lint Sources Tests Package.swift Examples` 0 violations; `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors` Build complete.
    - next: /review

    ```
    step: implement
    outcome: changed
    evidence: 8 files — StartedRuns.swift, AgentsTool.swift, AgentsToolContext.swift, AgentsToolOperations.swift, CheckAfterStartTests.swift (new), AgentSchedulingTests.swift, Support/ScriptedAgentModel.swift, Support/ScriptedTranscriptText.swift; swift test -Xswiftc -warnings-as-errors: 388 tests in 55 suites passed; swiftlint 0 violations; IntegrationTests build-tests complete
    task: ^x428x7j
    ```
  timestamp: 2026-09-28T23:00:23.970695+00:00
- actor: claude-code
  id: 01m3n47e7vm8khncrkv6dky9e2
  text: |-
    ### test — green
    - evidence: swift build -Xswiftc -warnings-as-errors — build complete, 0 errors; swift test -Xswiftc -warnings-as-errors — 388 tests, 55 suites, 0 failed; swiftlint lint Sources Tests Package.swift Examples — 0 violations, 0 serious, 133 files; cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors — build complete, 0 errors
    - next: none
  timestamp: 2026-09-28T23:05:01.947629+00:00
- actor: claude-code
  id: 01m3n4jwn8xqr90bdtnbhrt2dx
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD; 2 findings (2 confirmed, 0 refuted) — Tests/FoundationModelsAgentsTests/Support/ScriptedTranscriptText.swift:76, Tests/FoundationModelsAgentsTests/Support/ScriptedTranscriptText.swift:84
    - next: Correct the 2 open items in the "Review Findings (2026-09-28 18:05)" section. Then do the review again. The task stays in review.
  timestamp: 2026-09-28T23:11:17.160897+00:00
- actor: claude-code
  id: 01m3n4k7gtfg8509ck31v80mjp
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 8 files
    - test: green — swift test -Xswiftc -warnings-as-errors, 388 tests in 55 suites passed; swiftlint 0; IntegrationTests build-tests complete
    - commit: 9acf42b
    - review: findings — Tests/FoundationModelsAgentsTests/Support/ScriptedTranscriptText.swift:76, Tests/FoundationModelsAgentsTests/Support/ScriptedTranscriptText.swift:84
  timestamp: 2026-09-28T23:11:28.282591+00:00
- actor: claude-code
  id: 01m3n4v5g70by04jydpwg757a9
  text: |-
    Review findings (2026-09-28 18:05) corrected.
    - swift/fluent-usage: `ScriptedTranscriptText.idArguments(_:id:)` is now `idArguments(for:id:)`. The one call site (`ScriptedAgentModel.swift`, step `toolCallWithLastToken`) uses `for:`. The other functions of the file all have a first label already (`of:`, `in:`). Note: `AgentsToolMountTests` and `AgentSchedulingTests` each have a private `idArguments(_ operation:, of run:)` of the same shape. Those files were not in the scope of this finding, thus they did not change.
    - completeness/case-sensitivity-coverage: the token group of `completionTokenField` is now `(?i:[0-9A-HJKMNP-TV-Z]{26})`. Only the token is case-insensitive; the JSON field name `completionToken` still matches in its one case. The read gives the token with no change of case.
    - RED: new `ScriptedTranscriptTextTests.lowercaseCompletionTokenIsExtracted` failed first with `completionToken(in:) -> nil` for a lowercase ULID. GREEN after the regex change.

    ### implement — changed
    - evidence: Tests/FoundationModelsAgentsTests/Support/ScriptedTranscriptText.swift, Tests/FoundationModelsAgentsTests/Support/ScriptedAgentModel.swift, Tests/FoundationModelsAgentsTests/ScriptedTranscriptTextTests.swift (new); `swift test -Xswiftc -warnings-as-errors` 389 tests in 56 suites passed, 0 compiler warnings; `swiftlint lint Sources Tests Package.swift Examples` 0 violations in 134 files; `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors` Build complete.
    - next: /review

    ```
    step: implement
    outcome: changed
    evidence: 3 files — Tests/FoundationModelsAgentsTests/Support/ScriptedTranscriptText.swift, Tests/FoundationModelsAgentsTests/Support/ScriptedAgentModel.swift, Tests/FoundationModelsAgentsTests/ScriptedTranscriptTextTests.swift (new); swift test -Xswiftc -warnings-as-errors: 389 tests in 56 suites passed; swiftlint 0 violations in 134 files; IntegrationTests build-tests complete
    task: ^x428x7j
    ```
  timestamp: 2026-09-28T23:15:48.359666+00:00
- actor: claude-code
  id: 01m3n514qa7ckwge6a38n5z4th
  text: |-
    ### test — green
    - evidence: `swift build -Xswiftc -warnings-as-errors` — build OK, 0 compiler warnings; `swift test -Xswiftc -warnings-as-errors` — 389 tests in 56 suites, all pass, 0 fail, 0 skip; `swiftlint lint Sources Tests Package.swift Examples` — 0 violations in 134 files; `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors` — build OK, 0 compiler warnings
    - next: no action. The set of changes is clean.
  timestamp: 2026-09-28T23:19:04.170783+00:00
- actor: claude-code
  id: 01m3n58b8g8h8ezt41wr0nsfy7
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (66777ce): 1 finding, 1 confirmed, 0 refuted — Tests/FoundationModelsAgentsTests/ScriptedTranscriptTextTests.swift:13 (completeness/case-sensitivity-coverage)
    - next: Add one test that uses an uppercase completion token. Then run the review again. The task stays in review.
  timestamp: 2026-09-28T23:23:00.240314+00:00
- actor: claude-code
  id: 01m3n58mm91bcw0ehb8mntw6c2
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 3 files (idArguments(for:id:), case-insensitive token regex, lowercase token test)
    - test: green — swift test -Xswiftc -warnings-as-errors, 389 passed, 0 failed; swiftlint 0; IntegrationTests build-tests complete
    - commit: 66777ce
    - review: findings — Tests/FoundationModelsAgentsTests/ScriptedTranscriptTextTests.swift:13
  timestamp: 2026-09-28T23:23:09.833975+00:00
- actor: claude-code
  id: 01m3n5evqn3sv32q07q8k1bn6a
  text: |-
    Review finding (2026-09-28 18:19) corrected.
    - completeness/case-sensitivity-coverage: `ScriptedTranscriptTextTests` now has one parameterized test, `completionTokenIsExtracted(token:)`, with the arguments `lowercaseToken` ("01m3n4k7gtfg8509ck31v80mjp") and `uppercaseToken` ("01M3N4K7GTFG8509CK31V80MJP"). This test replaces `lowercaseCompletionTokenIsExtracted`. Both test cases pass. The read gives each token with no change of case.
    - Note: the test is for behavior that exists, thus it passed at the first run. No production code changed.
    - Note: the `dump validators` file was 754,245 characters. It was too large to read whole.

    ### implement — changed
    - evidence: Tests/FoundationModelsAgentsTests/ScriptedTranscriptTextTests.swift; `swift test -Xswiftc -warnings-as-errors` 389 tests in 56 suites passed (the filtered run shows 2 test cases for the new test), 0 compiler warnings; `swiftlint lint Sources Tests Package.swift Examples` 0 violations in 134 files.
    - next: /review

    ```
    step: implement
    outcome: changed
    evidence: 1 file — Tests/FoundationModelsAgentsTests/ScriptedTranscriptTextTests.swift; swift test -Xswiftc -warnings-as-errors: 389 tests in 56 suites passed (new parameterized test: 2 cases); swiftlint 0 violations in 134 files
    task: ^x428x7j
    ```
  timestamp: 2026-09-28T23:26:33.717207+00:00
- actor: claude-code
  id: 01m3n5mh3z518jbznr5hcn76wh
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 389 tests passed, 0 failed, 0 skipped, in 56 suites; `swiftlint lint Sources Tests Package.swift Examples` — 0 violations, 0 serious in 134 files; `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors` — build complete, no compiler warnings
    - next: ready for review/commit
  timestamp: 2026-09-28T23:29:39.455607+00:00
- actor: claude-code
  id: 01m3n5s8wt8vg7ggw0ce0dc7kq
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (2cd36b2) — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. 1 file reviewed. All prior findings are checked. All acceptance criteria are checked.
    - next: none. The task is in done.
  timestamp: 2026-09-28T23:32:14.874145+00:00
- actor: claude-code
  id: 01m3n5sfranrsk0299tbx8yd13
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — ScriptedTranscriptTextTests.swift, one parameterized test for both spellings
    - test: green — swift test -Xswiftc -warnings-as-errors, 389 passed, 0 failed; swiftlint 0; IntegrationTests build-tests complete
    - commit: 2cd36b2
    - review: clean — 0 findings
  timestamp: 2026-09-28T23:32:21.898233+00:00
position_column: done
position_ordinal: ba80
title: 'check agent and cancel agent right after start agent: the run can be absent before the start body adds it'
---
## Why
`start agent` is a background call with no `inlineSettleGrace` (^ggpyaem). The Router gives the pending envelope before the body of the call runs on the run plane. The body adds the run to the runner (`AgentRunner.startWithinLimit`) and to `StartedRuns` a short time later. A model that calls `check agent` or `cancel agent` at once, with the completion token or with no id, can get "No run has the id" or "You have no runs" for a run that starts some milliseconds later. The same gap makes some unit tests read `runner.runs(caller:)` too early; the tests now wait for a gate arrival or a `runSettled` event (see ^ggpyaem). `AgentSchedulingTests.checkWithNoIDListsOnlyRunsOfCaller` still reads the runs after the first gate arrival only.

## What
- Make `check agent` and `cancel agent` see a start call whose body did not add its run yet. For example: record the token of each background start call before the envelope goes back, and let `check agent` / `cancel agent` wait for the setup of that token (as `cancelRuns(caller:)` waits for `setups`).
- Make `checkWithNoIDListsOnlyRunsOfCaller` read the runs only after each start of the two callers added its run.

## Acceptance Criteria
- [x] A scripted test: a root session calls `start agent` and then `check agent` with the completion token in the next pass; the answer is the report of the run, never the unknown-id corrective.
- [x] `checkWithNoIDListsOnlyRunsOfCaller` has no race on the registration of the runs.

## Tests
- [x] `swift test -Xswiftc -warnings-as-errors` passes.

## Review Findings (2026-09-28 18:05)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsAgentsTests/Support/ScriptedTranscriptText.swift:76` `swift/fluent-usage` — The first argument label is omitted, but this is not a value-preserving conversion. Factory methods and functions that construct/format data must label all arguments to read as grammatical phrases at the call site. Change the parameter from `_ operation:` to `for operation:` (or another appropriate label), so the call reads: `ScriptedTranscriptText.idArguments(for: operation, id: ...)`.
- [x] `Tests/FoundationModelsAgentsTests/Support/ScriptedTranscriptText.swift:84` `completeness/case-sensitivity-coverage` — The new regex pattern `[0-9A-HJKMNP-TV-Z]{26}` is case-sensitive—it only matches uppercase letters. ULIDs use Crockford base-32 encoding, which is defined as case-insensitive. If the router ever generates lowercase completion tokens (e.g., `wf_abc123xyz...` instead of `WF_ABC123XYZ...`), this regex will fail to extract them. No test exercises lowercase completion tokens. Either update the regex to be case-insensitive—`(?i)[0-9A-HJKMNP-TV-Z]{26}`—or add a regression test that verifies the behavior when a lowercase token appears (either that it is rejected, or that it is normalized and accepted).

## Review Findings (2026-09-28 18:19)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsAgentsTests/ScriptedTranscriptTextTests.swift:13` `completeness/case-sensitivity-coverage` — The completionTokenField regex was changed to match tokens case-insensitively using (?i:[0-9A-HJKMNP-TV-Z]{26}), but the test only verifies lowercase tokens work. Testing an uppercase variant would confirm the case-insensitive matching actually applies to both canonical (lowercase) and non-canonical (uppercase) spellings, not just that lowercase happens to be accepted. Add one test that uses an uppercase token (e.g., '01M3N4K7GTFG8509CK31V80MJP') to verify the case-insensitive matching works for the non-canonical spelling.
