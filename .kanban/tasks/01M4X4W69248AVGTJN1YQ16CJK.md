---
assignees:
- claude-code
position_column: todo
position_ordinal: '8780'
title: A run can wait forever for the settlement of a child after a cancel during the answer that started it
---
## Defect (found in T1, not yet proved by a test)

`AgentRun.drive()` calls `sessionWatch.waitForSettlement(ofCalls:)` before `session.close()`. `ParentSessionWatch` learns that a call settled only from a live `SessionEvent.runSettled` (or from `finish()`, which comes only after the close).

The Router does not send the live events of a stopped answer: `RoutedSessionActorRunJournal.deliverLive(_:origin:)` sends nothing when `outputHub.drops(origin.poster)` is true. Thus when a caller cancels a run (`cancelAll()`) while the answer that started a child still runs, the `runSettled` of that `start agent` call does not come live, although the journal keeps it. Then `waitForSettlement` waits forever and the run never ends.

The subagent saw this hang in a draft of `CancelAllFinalMessageTests` (green variant), from code reading. The current test avoids the order.

## Proposed fix

Wait for the settlement by token through the run plane, not through the live event: for each child, `await child.context?.wait(completionToken:seconds: nil)` (public Extras API; it resumes at the settle, also when the live event is dropped). `waitForSettlement(ofCalls:)` stays by token. Other option: the Router always sends the terminal `runSettled` of a background run, also for a stopped answer (a terminal event, as the plan says).

## Test

A fixed-order test: the lead's task answer starts a child and is still open (gate); then `cancel()` on the lead; the run must end. Red before the fix. #mail-step-3