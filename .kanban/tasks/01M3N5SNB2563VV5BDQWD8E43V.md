---
assignees:
- claude-code
position_column: todo
position_ordinal: '9980'
title: 'Scheduling tests: wait for open start calls before they read runner.runs(caller:)'
---
## What
Three tests in `Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift` (and its extension files) read `runner.runs(caller:)` after the first gate arrival: `callerCannotCheckOrCancelRunOfOtherCaller`, `cancelRunsCancelsOnlyThatCaller` and `closeOfCallerCancelsOpenRun`. The body of `start agent` can add its run after that read. Thus a small race can make these tests fail.

Before each read, call `startedRuns.waitForStarts()` (added by ^x428x7j in `Sources/FoundationModelsAgents/Tool/StartedRuns.swift`). This is the same fix that ^x428x7j applied to `checkWithNoIDListsOnlyRunsOfCaller`.

Also, the private helpers `idArguments(_ operation:, of run:)` in `Tests/FoundationModelsAgentsTests/AgentsToolMountTests.swift` and `Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift` omit the first argument label. Label it (`idArguments(for:of:)`) to agree with `ScriptedTranscriptText.idArguments(for:id:)` and the swift/fluent-usage rule.

## Acceptance Criteria
- [ ] Each of the three tests waits for all open start calls before it reads `runner.runs(caller:)`.
- [ ] No test helper named `idArguments` has an unlabeled first argument.

## Tests
- [ ] `swift test -Xswiftc -warnings-as-errors --filter AgentSchedulingTests` passes 10 times in a row.
- [ ] `swift test -Xswiftc -warnings-as-errors` passes with 0 failures; `swiftlint lint Sources Tests Package.swift Examples` gives 0 violations.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.