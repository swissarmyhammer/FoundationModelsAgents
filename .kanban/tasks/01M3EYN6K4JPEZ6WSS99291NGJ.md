---
assignees:
- claude-code
position_column: todo
position_ordinal: '9380'
title: The reload burst test fails under CPU load
---
## What
The burst test that ^3qhg0xh wrote (commit 0e930cc) failed one time in a full run of `swift test -Xswiftc -warnings-as-errors` on 2026-09-26, while another process used much CPU:
- Test: "a burst of writes gives one final catalog with the last state, also when the burst spans two quiet periods" in `Tests/FoundationModelsAgentsTests/AgentRegistryReloadTests.swift`.
- Failed expectation: `#expect(later?.definitions.map(\.id) == nil)` — a second catalog came within one watcher quiet period after the full catalog.
- It passed 20 times alone and in 4 more full runs.

The check "no second catalog within one quiet period" depends on the wall clock. Under load, the watcher (`DotfolderWatcher` in FoundationModelsExtras) can see the last file events after a delay, and it then publishes one more catalog with the same content. A test that fails under load is a defect.

- Make the check prove the claim without a wall-clock race. Possible ways:
  - Assert that each catalog after the full one has the same ids and the same last description as the full one (no catalog with a partial or older state). This is the true claim: the final state wins, and no stale catalog comes later.
  - Or count reloads through a registry hook that tells when the watcher is quiet, if FoundationModelsExtras has one. Do not change FoundationModelsExtras from this repo.
- Keep the two cases: no pause, and a pause of two quiet periods.
- Show one time with a temporary change that the new check still fails when a stale catalog comes after the full one. Record the output as a comment on this task.

## Acceptance Criteria
- [ ] The burst test does not depend on the time between two catalogs.
- [ ] The test still fails when a catalog with an older state comes after the full catalog (temporary change, output recorded as a comment).
- [ ] The test passes 10 full runs of the suite in a row while another CPU load runs (for example, a parallel `swift build` of `IntegrationTests`).

## Tests
- [ ] Change `Tests/FoundationModelsAgentsTests/AgentRegistryReloadTests.swift`.
- [ ] Run `swift test -Xswiftc -warnings-as-errors` 10 times under load. Expected: pass each time. Report the real results.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.