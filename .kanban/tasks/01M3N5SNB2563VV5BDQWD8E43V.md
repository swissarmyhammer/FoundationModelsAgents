---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3ne6687qkhmp5wgjgbzwe11
  text: 'Research: The race is real. AgentRunner.start(_ request:) awaits AgentRun.start, and only then sets openRuns[run.id]. The child session can reach its gate step before that line runs. Thus gate.waitForArrival() does not prove that runner.runs(caller:) holds the run. StartedRuns.add(_:forCall:) runs in finalMessage(of:startedBy:) after the runner returns the run, so waitForStarts() returns only after the run is in the index. The three tests use Self.onlyRun(in:of:), which reads runner.runs(caller:). AgentsToolMountTests also reads runner.runs(caller:) after a start, but the task names only the three scheduling tests; that test is out of scope. Validators for .swift: code-hygiene, code-security, completeness, duplication, reuse, swift, test-integrity.'
  timestamp: 2026-09-29T01:59:06.759671+00:00
- actor: claude-code
  id: 01m3nerr67sn4r0nsn8f1ebrp4
  text: |-
    Implementation: The three tests read runner.runs(caller:) only through the private helper onlyRun(in:of:). The helper now calls `await harness.tool.context.startedRuns.waitForStarts()` before it reads. Thus the three tests get the fix, and the text is not copied three times. checkWithNoIDListsOnlyRunsOfCaller keeps its own wait, because it reads runs(caller:) directly before onlyRun. Both private helpers are now idArguments(for:of:), and their four call sites use the label.

    RED: I could not make the race fail before the fix. The three tests passed 300 repeats (`--maximum-repetitions 300 --repeat-until fail`) before the change. I added no sleeps and no waits on a clock.

    Environment: each swift test run shows SwiftPM warnings "failed loading cached manifest ... disk I/O error" and one "missing creator for mutated node" note. These come from the SwiftPM cache, not from the compiler. The -warnings-as-errors build passes.

    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift, Tests/FoundationModelsAgentsTests/AgentsToolMountTests.swift; `swift test -Xswiftc -warnings-as-errors --filter AgentSchedulingTests` 10 of 10 runs pass (11 tests in 3 suites each); `swift test -Xswiftc -warnings-as-errors` 424 tests in 62 suites pass, 0 failures; `swiftlint lint Sources Tests Package.swift Examples` 0 violations in 146 files.
    - next: review
  timestamp: 2026-09-29T02:09:14.951219+00:00
- actor: claude-code
  id: 01m3nfervkbvc329jq6f4xxz5x
  text: |-
    Extra reads fixed with `await harness.tool.context.startedRuns.waitForStarts()` before the read. The root session started each of these runs through `harness.tool`:
    - AgentsToolMountTests.listCheckAndCancelAnswerInBand.
    - FinalMessageTests.childRun(in:of:) helper (the reads after a gate arrival in startReturnsPendingEnvelopeAndRouterRecordsFinalMessage, cancelledRunGivesOneFinalMessage and finalMessageDuringCallerAnswerWaitsForNextSubmission). The wait is in the helper, the same as AgentSchedulingTests.onlyRun(in:of:).
    - NestedRunTests.failingParentCancelsChildThenPosts and cancelledParentCancelsChildThenPosts (the read of the lead).
    - NestedRunTests.Limits.waitingSiblingsLetChildrenStart (the read of the siblings).
    - MaxTurnsTests.hitMaxTurnsCancelsOpenChildThenPosts (the read of the lead).

    Not fixed here, because the fix does not apply: the run was not started through harness.tool. A run starts a child through its own agents tool (AgentRun.agentsTool(of:) makes a new AgentsToolContext for each run), and the CLI starts a run with no agents tool. The reads: AgentSchedulingTests+CallingRun limitDoesNotCountCallingRun, the read of the child of the lead in the NestedRunTests and MaxTurnsTests tests above and in NestedRunTests.parentFinishesAfterChild, and AgentsCLITests.cancelOfStartCancelsRun. New task ^5761w5h has them.

    SlashCommandTests.cancelOfTheStreamCancelsTheRun awaits `reader.value` before its read, thus the start has returned. AgentsToolOperationsTests reads after a direct `harness.call`, which returns after the body. These are not races.

    NestedRunTests.swift went to 403 lines (swiftlint file_length, limit 400) with a two-line comment at each wait. Thus the two waits in that file have no comment; the file has 399 lines.

    ### implement — changed
    - evidence: 6 files — Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift, AgentsToolMountTests.swift, FinalMessageTests.swift, MaxTurnsTests.swift, NestedRunTests.swift, NestedRunTests+Limits.swift; `swift test -Xswiftc -warnings-as-errors --filter "AgentSchedulingTests|AgentsToolMountTests"` 10 of 10 runs pass (16 tests in 4 suites each); `swift test -Xswiftc -warnings-as-errors` 424 tests in 62 suites pass, 0 failures; `swiftlint lint Sources Tests Package.swift Examples` 0 violations in 146 files.
    - next: review

    ```
    step: implement
    outcome: changed
    evidence: 6 files (AgentSchedulingTests, AgentsToolMountTests, FinalMessageTests, MaxTurnsTests, NestedRunTests, NestedRunTests+Limits); filter run 10/10 pass (16 tests, 4 suites); full swift test 424 tests in 62 suites pass; swiftlint 0 violations in 146 files
    task: ^wd8e43v
    ```
  timestamp: 2026-09-29T02:21:16.531354+00:00
- actor: claude-code
  id: 01m3ng1ktvds4v1bp6dy7j2b38
  text: |-
    ### test — green
    - evidence: `swift build -Xswiftc -warnings-as-errors` — build complete, 0 warnings from our code. `swift test -Xswiftc -warnings-as-errors` — 424 tests in 62 suites passed, 0 failures, 0 skipped. `swift test -Xswiftc -warnings-as-errors --filter AgentSchedulingTests` — 10 runs in a row, each 11 tests in 3 suites, all passed. `swiftlint lint Sources Tests Package.swift Examples` — 0 violations in 146 files. `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors` — build complete, 0 warnings from our code.
    - next: ready for review.
  timestamp: 2026-09-29T02:31:33.979494+00:00
position_column: doing
position_ordinal: '80'
title: 'Scheduling tests: wait for open start calls before they read runner.runs(caller:)'
---
## What
Three tests in `Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift` (and its extension files) read `runner.runs(caller:)` after the first gate arrival: `callerCannotCheckOrCancelRunOfOtherCaller`, `cancelRunsCancelsOnlyThatCaller` and `closeOfCallerCancelsOpenRun`. The body of `start agent` can add its run after that read. Thus a small race can make these tests fail.

Before each read, call `startedRuns.waitForStarts()` (added by ^x428x7j in `Sources/FoundationModelsAgents/Tool/StartedRuns.swift`). This is the same fix that ^x428x7j applied to `checkWithNoIDListsOnlyRunsOfCaller`.

The same race and the same fix also apply to these tests, which read the runs of a root session that started them through `harness.tool`, right after a gate arrival: `AgentsToolMountTests.listCheckAndCancelAnswerInBand`, `FinalMessageTests` (through its `childRun(in:of:)` helper), `NestedRunTests.failingParentCancelsChildThenPosts`, `NestedRunTests.cancelledParentCancelsChildThenPosts`, `NestedRunTests.Limits.waitingSiblingsLetChildrenStart` and `MaxTurnsTests.hitMaxTurnsCancelsOpenChildThenPosts`. The reads of runs that a run or the host starts are not in this task: ^5761w5h has them.

Also, the private helpers `idArguments(_ operation:, of run:)` in `Tests/FoundationModelsAgentsTests/AgentsToolMountTests.swift` and `Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift` omit the first argument label. Label it (`idArguments(for:of:)`) to agree with `ScriptedTranscriptText.idArguments(for:id:)` and the swift/fluent-usage rule.

## Acceptance Criteria
- [x] Each of the three tests waits for all open start calls before it reads `runner.runs(caller:)`.
- [x] No test helper named `idArguments` has an unlabeled first argument.

## Tests
- [x] `swift test -Xswiftc -warnings-as-errors --filter AgentSchedulingTests` passes 10 times in a row.
- [x] `swift test -Xswiftc -warnings-as-errors` passes with 0 failures; `swiftlint lint Sources Tests Package.swift Examples` gives 0 violations.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.