---
assignees:
- claude-code
position_column: todo
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
- [ ] Each read above waits until the runner has the run, with no sleep.

## Tests
- [ ] `swift test -Xswiftc -warnings-as-errors` passes with 0 failures; `swiftlint lint Sources Tests Package.swift Examples` gives 0 violations.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.