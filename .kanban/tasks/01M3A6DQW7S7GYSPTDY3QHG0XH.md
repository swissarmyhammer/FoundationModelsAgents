---
assignees:
- claude-code
depends_on:
- 01M3A6CJRDYEA2YJ9ANY4XPK60
- 01M3A6D97E9AZZKR1K4WWVNSC6
position_column: todo
position_ordinal: 8a80
title: 'Make two unit tests prove their claims: the reload burst and the waiting siblings'
---
## What
1. `AgentRegistryReloadTests.burstOfWritesGivesOneFinalCatalog` takes the first published catalog and expects all writes in it. On a busy CI machine, writes that take longer than the watcher's quiet period give a partial first catalog, and the test fails. It also does not prove that only one final catalog comes. Change it: wait with `onReload.first { <the last write is in it> }`, assert the full id list, and then assert that no second catalog comes within one watcher quiet period.
2. `NestedRunTests+Limits.waitingSiblingsLetChildrenStart` uses no gates, so the children end at once. It passes even if a waiting run still holds a slot. Change it: hold both children with gates, and wait until both siblings are in the waiting phase before the second child starts. Then release the gates.

## Acceptance Criteria
- [ ] The burst test passes when the writes are split over two quiet periods (a delay between two halves of the burst), and it fails if a second catalog comes after the full one.
- [ ] The sibling test fails if `isWorking` ignores `.waitingForChildren`. Prove this one time with a temporary change during development, and record the failing output as a comment on this task.

## Tests
- [ ] The two changed tests.
- [ ] Run each test 5 times alone, then the full suite. Expected: pass each time.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.