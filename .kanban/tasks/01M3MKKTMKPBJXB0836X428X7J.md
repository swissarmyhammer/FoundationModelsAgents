---
assignees:
- claude-code
position_column: todo
position_ordinal: '9380'
title: 'check agent and cancel agent right after start agent: the run can be absent before the start body adds it'
---
## Why
`start agent` is a background call with no `inlineSettleGrace` (^ggpyaem). The Router gives the pending envelope before the body of the call runs on the run plane. The body adds the run to the runner (`AgentRunner.startWithinLimit`) and to `StartedRuns` a short time later. A model that calls `check agent` or `cancel agent` at once, with the completion token or with no id, can get "No run has the id" or "You have no runs" for a run that starts some milliseconds later. The same gap makes some unit tests read `runner.runs(caller:)` too early; the tests now wait for a gate arrival or a `runSettled` event (see ^ggpyaem). `AgentSchedulingTests.checkWithNoIDListsOnlyRunsOfCaller` still reads the runs after the first gate arrival only.

## What
- Make `check agent` and `cancel agent` see a start call whose body did not add its run yet. For example: record the token of each background start call before the envelope goes back, and let `check agent` / `cancel agent` wait for the setup of that token (as `cancelRuns(caller:)` waits for `setups`).
- Make `checkWithNoIDListsOnlyRunsOfCaller` read the runs only after each start of the two callers added its run.

## Acceptance Criteria
- [ ] A scripted test: a root session calls `start agent` and then `check agent` with the completion token in the next pass; the answer is the report of the run, never the unknown-id corrective.
- [ ] `checkWithNoIDListsOnlyRunsOfCaller` has no race on the registration of the runs.

## Tests
- [ ] `swift test -Xswiftc -warnings-as-errors` passes.