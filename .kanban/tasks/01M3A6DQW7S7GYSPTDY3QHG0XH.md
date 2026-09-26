---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3ewscr0w3yecgrndmkr961g
  text: |-
    Research:
    - The registry watcher is `DotfolderWatcher(roots:)` with the default quiet period `DotfolderWatcher.defaultDebounceInterval` (200 ms, a `DispatchTimeInterval`). The test gets a `Duration` from it through `DispatchTime` arithmetic, thus no bare number and no switch with a `default:`.
    - Each `onReload` access is a new subscription. The burst test waits with `first { <last burst agent is in it> }`, then races a second read against one quiet period.
    - Each slot has one generation gate, and a gated turn holds it for its whole turn. The old sibling test has root, both leads and test-writer on `standard`. Thus a gate in the task turn of the second lead can deadlock the first lead. Plan: use the temporary layer of `Limits` — `planner` (standard, `tools: Agent`) and `flash-lead` (flash, `tools: Agent(helper)`). `helper` has no model and takes the slot of its parent. The root starts `planner` first, then `flash-lead` (thus the second start sees only one working run). The `planner` play waits on a sibling gate before its `start agent` call. The test opens that gate only after `flash-lead` is in `.waitingForChildren` and its gated helper arrived. Then it waits until `planner` waits (or ended), and opens the two helper gates.
    - With the fix gone (`isWorking` ignores `.waitingForChildren`), the start of the second helper sees `flash-lead` + the first helper = 2 working runs, and gets the at-limit corrective.
  timestamp: 2026-09-26T12:59:35.040381+00:00
- actor: claude-code
  id: 01m3ewy2rb2dahzzyry79qxhwb
  text: |-
    Proof for the sibling test (acceptance criterion 2). Temporary change in `AgentRun.isWorking`: `storage.state == .running && storage.progress.phase != .waitingForChildren` became `storage.state == .running`. Command: `swift test -Xswiftc -warnings-as-errors --filter waitingSiblingsLetChildrenStart`. The new gated test failed with 4 issues:

    ```
    Test "with maxConcurrentAgents 2, two waiting siblings hold no place, and their children start" recorded an issue at NestedRunTests+Limits.swift:195:13: Expectation failed: secondPhase == .waitingForChildren
      secondPhase → .delivery
    ... recorded an issue at NestedRunTests+Limits.swift:196:13: Expectation failed: children.map(\.agent.id) == [Self.helper, Self.helper]
      children.map(\.agent.id) → ["helper"]
    ... recorded an issue at NestedRunTests+Limits.swift:197:13: Expectation failed: refusals.isEmpty
      refusals → ["2 agents are working now, and that is the limit. Do this part of the task yourself, or start the agent when one of them finishes."]
    ... recorded an issue at NestedRunTests+Limits.swift:199:13: Expectation failed: secondResult.contains(Self.secondHelperText)
      secondResult → "I started the agents."
    Test ... failed after 0.053 seconds with 4 issues.
    ```

    Note: with the same temporary change, the old ungated test also failed in one run (the reviewer child on `flash` was still open). That failure came from the timing of the run, not from the structure of the test. The new test holds each child with a gate and orders the second start after the first sibling waits, thus the failure is certain. The temporary change is reverted.
  timestamp: 2026-09-26T13:02:08.651202+00:00
- actor: claude-code
  id: 01m3ex894gpgpzajepvkjd1044
  text: |-
    Burst test proof (acceptance criterion 1):
    - RED for the old test: a temporary pause of 400 ms before the third write made the old `burstOfWritesGivesOneFinalCatalog` fail with 3 issues. The first catalog held only `burst-agent-0`, `burst-agent-1`, `live-agent`, and the description was `burst-agent-1`.
    - The new test takes the pause as an argument: `Duration.zero` and `splitPause` (two watcher quiet periods, from `DotfolderWatcher.defaultDebounceInterval`). It waits with `first { <burst-agent-4 is in it> }`, asserts the full id list, and asserts that no catalog comes within one quiet period. Both cases pass.
    - Proof of the last assertion: a temporary `try await registry.reload()` after the full catalog made both cases fail at `later == nil`. The temporary change is reverted. The assertion now reads `later?.definitions.map(\.id) == nil`, thus a failure prints the ids and not the whole catalog.
    - `NestedRunTests.pollInterval` is now internal: the sibling test uses it to wait for the phase of a run.
  timestamp: 2026-09-26T13:07:42.864413+00:00
- actor: claude-code
  id: 01m3ex8bk430a40k6d128c11b7
  text: |-
    ### implement — changed
    - evidence: 3 files — Tests/FoundationModelsAgentsTests/AgentRegistryReloadTests.swift, Tests/FoundationModelsAgentsTests/NestedRunTests+Limits.swift, Tests/FoundationModelsAgentsTests/NestedRunTests.swift. No change in Sources (the temporary `isWorking` change is reverted). `swift build -Xswiftc -warnings-as-errors` clean; each changed test 5 times alone: 5/5 pass (burst: 2 cases each run); `swift test -Xswiftc -warnings-as-errors`: 359 tests in 49 suites pass; `cd IntegrationTests && swift build --build-tests`: complete; swiftlint: 0 violations in 123 files.
    - next: /review
  timestamp: 2026-09-26T13:07:45.380638+00:00
- actor: claude-code
  id: 01m3exfeeqgrwh765xktmgec39
  text: |-
    ### review — clean
    - step: review
    - outcome: clean
    - evidence: 0 findings (review sha HEAD~1..HEAD at 0e930cc; 3 files reviewed, 4 .kanban files excluded by .reviewignore; confirmed 0, refuted 0, failed 0)
    - next: none. The task moved to done.
  timestamp: 2026-09-26T13:11:37.687134+00:00
- actor: claude-code
  id: 01m3exfmqbxk0dj29yv1zbbmj1
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 test files
    - test: green — swift test -Xswiftc -warnings-as-errors, 359 passed; swiftlint 0; IntegrationTests build --build-tests passes
    - commit: 0e930cc
    - review: clean — 0 findings
  timestamp: 2026-09-26T13:11:44.107991+00:00
depends_on:
- 01M3A6CJRDYEA2YJ9ANY4XPK60
- 01M3A6D97E9AZZKR1K4WWVNSC6
position_column: done
position_ordinal: ad80
title: 'Make two unit tests prove their claims: the reload burst and the waiting siblings'
---
## What
1. `AgentRegistryReloadTests.burstOfWritesGivesOneFinalCatalog` takes the first published catalog and expects all writes in it. On a busy CI machine, writes that take longer than the watcher's quiet period give a partial first catalog, and the test fails. It also does not prove that only one final catalog comes. Change it: wait with `onReload.first { <the last write is in it> }`, assert the full id list, and then assert that no second catalog comes within one watcher quiet period.
2. `NestedRunTests+Limits.waitingSiblingsLetChildrenStart` uses no gates, so the children end at once. It passes even if a waiting run still holds a slot. Change it: hold both children with gates, and wait until both siblings are in the waiting phase before the second child starts. Then release the gates.

## Acceptance Criteria
- [x] The burst test passes when the writes are split over two quiet periods (a delay between two halves of the burst), and it fails if a second catalog comes after the full one.
- [x] The sibling test fails if `isWorking` ignores `.waitingForChildren`. Prove this one time with a temporary change during development, and record the failing output as a comment on this task.

## Tests
- [x] The two changed tests.
- [x] Run each test 5 times alone, then the full suite. Expected: pass each time.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.