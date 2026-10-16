---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53jgcnv2xj7rph1qxz19aqm
  text: |-
    ### done
    - commits 8efae76 (RelayedQuestionTests: firstQuestion, withParts, the delivery before finalState), 2b6b78c (waits for the gate of a child and for a settlement), 410673e (gates, streams and fixtures), the reload/play-gate commit after it, and 572952a (three more gate waits).
    - New helpers: `ScriptedGate.waitForArrival(orEndOf:)` (run and task forms), `ScriptedGate.wait(orEndOf:)`, `requirePendingStarts(count:)`, `requireMessageSentToCaller()`, `requireMessageSent(beforeGate:)`.
    - Registry reload waits: option A of the coordinator. Extras 6959dd7 gives no public or package seam for hand-given file events.
    - The waits that stay are on ^6w3yneh (14 reload waits, 9 other waits).
    - No `.timeLimit`, sleep, poll or retry was added (checked with rg on the diff).
    - One full run: 583 tests in 80 suites passed in 2.338 s.
  timestamp: 2026-10-16T23:59:39.195967+00:00
position_column: done
position_ordinal: ea80
title: 'Test rule T1: each test wait also ends on the failure event'
---
Source: elicitation-plan.md section 10, the check of 2026-10-16.

Rule T1: each wait in a test must also end on the failure event (the run settles, the session closes, the stream ends), or the test must fail before it waits. A fixture must also close when the test body throws. NestedRunTests+Pause is the good example: it opens its gates on an error.

Known places:
- [ ] RelayedQuestionTests `firstQuestion` (~199-213) stops only at a question or `runSettled`.
- [ ] RelayedQuestionTests `withParts` (~187-189) does not close the root when the body throws.
- [ ] RelayedQuestionTests `child.finalState()` waits (~259, ~286-287) have no exit.
- [ ] Search the whole test target for other waits of this type, and correct each one.
- [ ] No `.timeLimit`, sleep, poll or retry.
- [ ] One full run is green. #elicitation-check #bug