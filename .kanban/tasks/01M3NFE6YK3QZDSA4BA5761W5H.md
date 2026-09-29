---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3ngj1741ycxt3ak0dn8r8qh
  text: 'Research: The gap is in production code, thus a production fix closes it for each caller (tool, nested run, CLI, host). AgentRun.start makes the session and starts the driver in one call. AgentRunner.start(_ request:) puts the run in openRuns only after that call returns, and the actor can run other calls before it continues. Plan: split AgentRun.start in two. AgentRun.make does the setup only (the session gets no prompt). The runner puts the run in openRuns, then calls run.begin(_:environment:), which adds the run to the children of its parent and starts the driver. These steps run on the actor with no suspension between them, thus the run is in the index before its session can call a tool or reach a gate. The setup waiters of cancelRuns resume after begin, as before. AgentRunHarness.start (test support, the only other caller of AgentRun.start) calls make then begin. A deterministic RED at the runner is not possible with the old code (the race depends on actor scheduling; ^wd8e43v saw 300 passes). The RED is the new make/begin test: a made run sends no prompt before begin.'
  timestamp: 2026-09-29T02:40:31.972767+00:00
- actor: claude-code
  id: 01m3nmhtf4ca6ksyx1fev95tdn
  text: |-
    Implementation: a production fix closes the gap for each caller, thus the tests need no new wait.
    - `AgentRun.start` is now two calls. `internal static func make(_:environment:renderer:)` does the setup and sends no prompt. `internal func begin(_:environment:)` adds the run to the children of its parent and starts the driver. A run whose setup failed has no session, thus `begin` does nothing for it.
    - `AgentRunner.start(_ request:)` calls `make`, puts the run in `openRuns`, then calls `begin`, then resumes the setup waiters. There is no suspension between the index write and `begin`, thus the run is in the index before its session can call a tool or reach a gate. The five reads that the card names (CallingRun, three NestedRunTests, MaxTurnsTests, AgentsCLITests.cancelOfStartCancelsRun) now always find the run. No test file of the card changed.
    - `AgentRunHarness` (test support) gets `request(_:prompt:context:agentsTool:)` and `makeRun(_:)`; `start` calls `makeRun` then `begin`.
    - AgentRun.swift has 395 lines.

    TDD: RED was a compile failure: `type 'AgentRun' has no member 'make'` and `value of type 'AgentRun' has no member 'begin'` (new test `madeRunSendsNoPromptUntilBegin`). A runtime RED of the old race is not possible: it depends on actor scheduling. New test `runIsInIndexWhenItsSessionRuns` pins the invariant: a read of `runs(caller: nil)` at a gate arrival, before `start` returns, finds the run.

    Discovery: in the first 10-run loop of the affected suites, runs 5 and 10 failed: `limitDoesNotCountCallingRun` (`result.contains(Self.childText)`) and the maxDepth 2 test (`result.contains(Self.childPlannerText)`). One more run with `--maximum-repetitions 50 --repeat-until fail` showed `waitingSiblingsLetChildrenStart` and `parentAndChildOnOneModel` (`result == prompts.last`, while `prompts.last` holds the child report). In each one the parent ends with the reply of an earlier answer. The probable cause is the idle check at a `runSettled` event: it reads the live transcript, which can hold the mail prompt before the follower processed `submissionStarted`. In the CallingRun test the child is adopted long before the gates open, thus the new start order is not in that window. The old code passed 25 of 25 loops, and the new code 18 of 20, so I cannot prove that the frequency did not change. New task ^saqyk70 has the details. A second 10-run loop of the new code passed 10 of 10. Also: an in-process `--maximum-repetitions 50` run of the OLD code hung for more than 30 minutes, thus in-process repetition does not give a clean comparison.
  timestamp: 2026-09-29T03:50:19.364253+00:00
- actor: claude-code
  id: 01m3nmj11t2z9escrbx7r127y8
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsAgents/Run/AgentRun.swift, Sources/FoundationModelsAgents/Run/AgentRunner.swift, Tests/FoundationModelsAgentsTests/AgentRunTests.swift, Tests/FoundationModelsAgentsTests/AgentRunnerTests.swift, Tests/FoundationModelsAgentsTests/Support/AgentRunHarness.swift. `swift test -Xswiftc -warnings-as-errors --filter 'AgentRunTests|AgentRunnerTests|AgentSchedulingTests|NestedRunTests|MaxTurnsTests|AgentsCLITests|FinalMessageTests|AgentsToolMountTests'`: last loop 10 of 10 runs pass (96 tests in 15 suites each); the first loop was 8 of 10 (see the comment above and ^saqyk70). `swift test -Xswiftc -warnings-as-errors`: 426 tests in 62 suites pass. `swiftlint lint Sources Tests Package.swift Examples`: 0 violations in 146 files. `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors`: build complete.
    - next: review

    ```
    step: implement
    outcome: changed
    evidence: 5 files (AgentRun.swift, AgentRunner.swift, AgentRunTests.swift, AgentRunnerTests.swift, Support/AgentRunHarness.swift); filter loop 10/10 pass (96 tests, 15 suites) after an earlier 8/10 loop (idle race, ^saqyk70); full swift test 426 tests in 62 suites pass; swiftlint 0 violations in 146 files; IntegrationTests build-tests complete
    task: ^5761w5h
    ```
  timestamp: 2026-09-29T03:50:26.106540+00:00
- actor: claude-code
  id: 01m3npweh6r81qctg229c9j5fr
  text: |-
    ### test — green
    - evidence: `swift build -Xswiftc -warnings-as-errors` — exit 0, 0 compiler warnings. `swift test -Xswiftc -warnings-as-errors` — 426 tests in 62 suites passed, 0 failures, 0 skipped. `swiftlint lint Sources Tests Package.swift Examples` — 0 violations in 146 files. `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors` — exit 0, 0 compiler warnings.
    - the known idle-race nested-run failure (task ^saqyk70) did not occur in this run, so the two extra full-suite runs were not needed.
    - next: task is ready for review.
  timestamp: 2026-09-29T04:31:04.742897+00:00
position_column: doing
position_ordinal: '80'
title: 'Tests: wait for the runner index of runs that a run or the host starts, before a read of runner.runs(caller:)'
---
## What
Some tests read `runner.runs(caller:)` right after a gate arrival, but the run was not started through the `agents` tool of the test harness. Thus `harness.tool.context.startedRuns.waitForStarts()` (the fix of ^wd8e43v) does not apply to them.

`AgentRunner.start(_ request:)` awaits `AgentRun.start`, and only then sets `openRuns[run.id]`. `AgentRun.start` starts the driver of the session before it returns. Thus the child session can arrive at its gate before the runner has the run, and the read can miss the run.

The reads:
- `Tests/FoundationModelsAgentsTests/AgentSchedulingTests+CallingRun.swift`, `limitDoesNotCountCallingRun`: reads `runs(caller: parent.id)` after `childGate.waitForArrival()`. The parent run starts the child through its own `agents` tool (`AgentRun.agentsTool(of:)` makes a new `AgentsToolContext` for each run), not through `harness.tool`.
- `Tests/FoundationModelsAgentsTests/NestedRunTests.swift`: `parentFinishesAfterChild`, `failingParentCancelsChildThenPosts` and `cancelledParentCancelsChildThenPosts` read `onlyRun(of:caller: lead.id)` after a gate arrival of the child. The lead starts the child through its own `agents` tool.
- `Tests/FoundationModelsAgentsTests/MaxTurnsTests.swift`, `hitMaxTurnsCancelsOpenChildThenPosts`: reads `onlyRun(of:caller: lead.id)` after a gate arrival of the child. Same cause.
- `Tests/FoundationModelsAgentsTests/AgentsCLITests.swift`, `cancelOfStartCancelsRun`: reads `runs(caller: nil)` after `gate.waitForArrival()`, while the task of `agent start` can still be in `AgentRunner.start`. No `agents` tool is in the path.

Find a test-visible way to wait until the runner has the run (for example a wait on the open setups of the runner, or a read of the children of the parent run), and use it before each read above. Do not add sleeps or waits on a clock.

## Acceptance Criteria
- [x] Each read above waits until the runner has the run, with no sleep.

## Tests
- [x] `swift test -Xswiftc -warnings-as-errors` passes with 0 failures; `swiftlint lint Sources Tests Package.swift Examples` gives 0 violations.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.