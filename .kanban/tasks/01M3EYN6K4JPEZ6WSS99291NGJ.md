---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3ffq1558vr9j0f6vwtzmf4a
  text: |-
    Research:
    - `AgentRegistry.build()` takes a build number before it reads the files, and it publishes under the `current` lock only when the number is higher than the current number. Thus `onReload` gets the catalogs in build order, and a build that reads an older disk state cannot publish after a newer build.
    - Each `onReload` subscriber stream has no buffer limit (`AgentCatalogBroadcaster.subscribe()` uses the default policy). Thus the test sees each catalog that the registry publishes.
    - `reload()` is synchronous work behind `async`: when it returns, its catalog is in each subscriber stream (or a newer build with a higher number is there already, and that build read the disk after the write).
    - Plan: after the full catalog, write a marker agent file and call `registry.reload()`. Then read the stream up to the first catalog that holds the marker, with `prefix(while:)`. Each catalog before the marker must have the full id list and the last description. This check has no time limit and no race: the marker gives a known end. The `catalog(on:within:)` helper goes away.
  timestamp: 2026-09-26T18:30:20.581600+00:00
- actor: claude-code
  id: 01m3ffsbmv5n95r765wt9ds0p5
  text: |-
    Proof for acceptance criterion 2. The temporary change was 3 lines in the test, after the full catalog and before the marker read:

    ```
    // TEMPORARY: a catalog with an older state after the full catalog.
    try layer.write(Self.agentText(description: Self.burstAgentIDs[1]), at: Self.agentPath)
    try layer.remove(Self.filePath(of: lastID))
    try await registry.reload()
    ```

    Command: `swift test -Xswiftc -warnings-as-errors --filter burstOfWritesEndsWithTheLastState`. Result: both cases (pause 0.0 s and 0.4 s) failed, 6 issues. The two new checks failed in each case:

    ```
    Test "a burst of writes ends with the last state, and no catalog with an older state comes after it, also when the burst spans two quiet periods" recorded an issue with 1 argument pause → 0.4 seconds at AgentRegistryReloadTests.swift:201:9: Expectation failed: later.map { $0.definitions.map(\.id) } == Array(repeating: fullIDs, count: later.count)
      later.map { $0.definitions.map(\.id) } → [["burst-agent-0", "burst-agent-1", "burst-agent-2", "burst-agent-3", "live-agent"]]
      Array(repeating: fullIDs, count: later.count) → [["burst-agent-0", "burst-agent-1", "burst-agent-2", "burst-agent-3", "burst-agent-4", "live-agent"]]
    ... at AgentRegistryReloadTests.swift:202:9: Expectation failed: later.map { Self.description(in: $0) } == Array(repeating: Optional(lastID), count: later.count)
      later.map { Self.description(in: $0) } → [Optional("burst-agent-1")]
      Array(repeating: Optional(lastID), count: later.count) → [Optional("burst-agent-4")]
    ... at AgentRegistryReloadTests.swift:203:9: Expectation failed: Self.description(in: registry.catalog()) == lastID
      Self.description(in: registry.catalog()) → "burst-agent-1"
    Test ... with 2 test cases failed after 0.642 seconds with 6 issues.
    ```

    The pause 0.0 s case failed with the same 3 issues. The temporary change is reverted.
  timestamp: 2026-09-26T18:31:36.859949+00:00
- actor: claude-code
  id: 01m3fg6bww5y3q8m1nc2rsm8wa
  text: |-
    Implementation:
    - The test is now `burstOfWritesEndsWithTheLastState` ("a burst of writes ends with the last state, and no catalog with an older state comes after it, also when the burst spans two quiet periods"). It keeps the two cases: `Duration.zero` and `splitPause` (two quiet periods).
    - After the full catalog, the new helper `catalogsBeforeMarker(on:of:in:)` writes the agent `marker-agent`, calls `registry.reload()`, and reads `onReload` with `prefix(while:)` up to the first catalog that holds the marker. Each catalog before the marker must have the full id list and the description `burst-agent-4`. The read has no time limit and no race: `reload()` puts a catalog with the marker in the stream before it returns.
    - The `catalog(on:within:)` helper (the wall-clock race) is removed. The new helper `filePath(of:)` gives the path of an agent file; `agentPath` and `writeBurst` use it.
    - Load for the 10 runs: 18 `yes > /dev/null` processes (one for each core). The load average was 21 to 58 during the runs. All 18 processes were killed after the runs (0 left). No build folder was deleted.
  timestamp: 2026-09-26T18:38:43.100201+00:00
- actor: claude-code
  id: 01m3fg6gky04caq3n5z8e3gy8n
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsAgentsTests/AgentRegistryReloadTests.swift. No change in Sources or in FoundationModelsExtras. RED: with the temporary stale-catalog change, `--filter burstOfWritesEndsWithTheLastState` failed in both cases with 6 issues (change reverted). GREEN: `--filter AgentRegistryReloadTests` 10 tests in 1 suite pass. `swift build -Xswiftc -warnings-as-errors`: Build complete. swiftlint: 0 violations in 123 files. `swift test -Xswiftc -warnings-as-errors` 10 full runs in a row under 18 `yes` processes (load average 21 to 58): runs 1-10 each exit 0, 359 tests in 49 suites passed (1.276 s, 0.781 s, 0.891 s, 0.727 s, 0.772 s, 0.783 s, 0.778 s, 0.809 s, 0.907 s, 0.853 s); the burst test passed in 10/10 runs (2 cases each). The only warning line in each log is the SwiftPM build-system line `missing creator for mutated node` for the mlx-swift_Cmlx bundle. It was there before this change, and it is not a compiler warning.
    - next: /review
  timestamp: 2026-09-26T18:38:47.934410+00:00
- actor: claude-code
  id: 01m3fgff53znw2kgz84pqsj4fe
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (bf0016d). 0 findings (7 validator runs attempted, 0 failed). 1 file reviewed. 4 .kanban files not reviewed because of .reviewignore.
    - next: none. The task moved to done.

    ```
    step: review
    outcome: clean
    evidence: 0 findings
    task: ^9291ngj
    ```
  timestamp: 2026-09-26T18:43:41.347903+00:00
- actor: claude-code
  id: 01m3fgfmyyge5bmprtyztpvqxy
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — AgentRegistryReloadTests.swift; 10 loaded runs 359/359 each
    - test: green — swift test -Xswiftc -warnings-as-errors, 359 passed; swiftlint 0; IntegrationTests build passes
    - commit: bf0016d
    - review: clean — 0 findings
  timestamp: 2026-09-26T18:43:47.294320+00:00
position_column: done
position_ordinal: b080
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
- [x] The burst test does not depend on the time between two catalogs.
- [x] The test still fails when a catalog with an older state comes after the full catalog (temporary change, output recorded as a comment).
- [x] The test passes 10 full runs of the suite in a row while another CPU load runs (for example, a parallel `swift build` of `IntegrationTests`).

## Tests
- [x] Change `Tests/FoundationModelsAgentsTests/AgentRegistryReloadTests.swift`.
- [x] Run `swift test -Xswiftc -warnings-as-errors` 10 times under load. Expected: pass each time. Report the real results.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.