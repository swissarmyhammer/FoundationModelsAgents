---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37svwx49cjsvzg1jk590c87
  text: |-
    ### Research
    - The Router generation gate is held for the WHOLE turn (RoutedSessionActorTurnGating admits turnLock, then generationGate, at turn start). A tool call in the turn does not release it, except `awaitingUser`. Thus a gated tool does not free the slot. Plan: each gated run is on its own slot (code-reviewer = flash, test-writer = standard). A root session on standard can start a child on standard: the child turn waits for the gate until the root turn ends.
    - `ToolContext.init` is internal to the Router. A test gets a caller only through a real root session that calls the tool. For "check/cancel with the id of a different caller", the script needs the id at run time: add a deferred tool-call step (a Sendable box that the test fills) to the scripted model. To read the tool answers in a root session, the script records each `.toolOutput` text.
    - `SessionEvent` has no library evolution and asks for a `default` arm; the review rule forbids a `default` that hides cases. The `lastEvent` phrase table uses `if case` tests, not a `switch`.
    - Check with no id: one block for each run of the caller (`runner.runs(caller:)` reports), joined with a blank line. No run: "You have no runs." as a success.
    - Limit: count of open runs in `.running`, plus the starts in setup (actor reentrancy at `await AgentRun.start`). Only `start agent` checks it.
  timestamp: 2026-09-23T18:53:50.372533+00:00
- actor: claude-code
  id: 01m37y52gbtr9yb43vac2gnzs3
  text: |-
    ### implement — changed
    - evidence: Run/AgentRunActivity.swift (new, lastEvent phrases), Run/AgentRun.swift (lastEvent), Run/AgentRun+FinalMessage.swift ("is running: lastEvent."), Run/AgentRunner.swift (startWithinLimit, LimitedStart, cancelRuns(caller:), shared cancel), Tool/AgentsToolText.swift (atLimit, reports, noRuns; missingID removed), Tool/AgentsToolContext.swift (caller isolation, reportsOfCallerRuns), Tool/AgentsToolOperations.swift; Tests: AgentSchedulingTests.swift (new, 7 tests), Support/ScriptedArguments.swift (new), Support/ScriptedAgentModel.swift (deferredToolCall, toolOutputs), Support/AgentRunHarness.swift + AgentsToolHarness.swift (maxConcurrentAgents), AgentsToolOperationsTests.swift + FinalMessageTests.swift updated.
    - discovery: FinalMessageTests.cancelledRunPostsOneCompleted cancelled a root-started child with a host call (caller nil). Caller isolation now refuses that, and `finalState()` waited for ever (the whole test process hung, no worker threads). The test now cancels through `runner.cancelRuns(caller: root.id)`.
    - discovery: stdout of `swift test` into a file is block-buffered; a hung run prints nothing. Run single tests with `timeout` to find a hang.
    - next: test
  timestamp: 2026-09-23T20:08:45.323198+00:00
- actor: claude-code
  id: 01m37yak421rn7w5gnzfr6kpay
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 217 tests in 28 suites passed, 0 failed, 0 skipped; `swiftlint lint --quiet Sources Tests Examples` — 0 violations (after line-length and type-body-length fixes in AgentSchedulingTests; the phrase test moved to AgentRunActivityTests.swift).
    - next: commit
  timestamp: 2026-09-23T20:11:46.178569+00:00
- actor: claude-code
  id: 01m37yawz2359s6hmeaeqsydah
  text: |-
    ### commit — changed
    - evidence: 4493dbf feat(scheduler): start agent checks maxConcurrentAgents, callers see only their own runs, and cancelRuns(caller:) cancels one caller
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T20:11:56.258281+00:00
- actor: claude-code
  id: 01m37ygp20a8p61r9af6bayz1r
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (4493dbf) — 0 findings, 0 confirmed, 0 refuted; 7 validator runs, 0 failed; 15 files reviewed (.kanban excluded by .reviewignore). No prior findings.
    - next: done

    ### finish iteration 1 — clean
    - implement: changed (11 source/test files + 4 new files)
    - test: green — 217 tests in 28 suites, 0 failed, 0 skipped; swiftlint 0 violations; -warnings-as-errors clean
    - commit: changed — 4493dbf
    - review: clean — 0 findings
  timestamp: 2026-09-23T20:15:05.792048+00:00
depends_on:
- 01M376H7W3JTVB6X8M5GBDQNNN
position_column: done
position_ordinal: '9280'
title: 'Scheduler: maxConcurrentAgents, caller isolation, cancelRuns(caller:), check with no id'
---
## What
Plan.md §9.2 (a closed caller), §9.3 (the limit, the index). M5, first part.

- In `Sources/FoundationModelsAgents/Run/AgentRunner.swift` (or a new `AgentRunner+Scheduling.swift`):
  - `maxConcurrentAgents` counts runs with a turn in operation. Only `start agent` checks it. At the limit the tool gives the corrective: "`N` agents are working now, and that is the limit. Do this part of the task yourself, or start the agent when one of them finishes." No queue. Host-driven `runner.start` does not check it.
  - `cancelRuns(caller: ULID)`: cancel each open run of that caller.
- In `Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift`:
  - `check agent` with no `id`: one block for each run of this caller.
  - `check agent` and `cancel agent` with an id of a different caller: the same corrective as an unknown id, with this caller's ids.
  - Running text: "is running: `lastEvent`".
- Verify (plan.md §16): a post into a closed session does no harm.

## Acceptance Criteria
- [x] With `maxConcurrentAgents` 2 and two gated runs, a third `start agent` gives the corrective; after one finishes, a new start succeeds.
- [x] Caller A cannot check or cancel a run of caller B.
- [x] `check agent` with no id lists only the runs of the caller.
- [x] `cancelRuns(caller:)` cancels only that caller's runs.
- [x] A run that finishes after its caller session closed does not crash and gives its record.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift` covers each criterion.
- [x] Run `swift test --filter AgentSchedulingTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.