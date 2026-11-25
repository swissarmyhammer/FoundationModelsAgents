---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m88xnbsjg09by0z9tdbq7qaw
  text: |-
    ### test — green
    - evidence: `swift test`: 1009 tests in 132 suites pass.
    - The new suite RestoreModelChangeTests failed first with `modelMismatch`, and passes after the fix.
    - The Router update changed one contract (Router a6830069): a damaged `index.md` does not fail the list of the children. The test `facadeReportsUnreadableRecording` now pins the new result: the child above the damaged record fails with `indexUnreadable` in `report.failed`.
    - The test support follows the Router API: `ModelLoader.loadLLM` has `kvCache`, and the scripted profile gives the flash model to the `decision` slot.
    - next: commit and push, then send the sha to TestudoApp and to foundationmodelsrouter-09.
  timestamp: 2026-11-25T08:37:54.098113+00:00
position_column: done
position_ordinal: ffa080
title: A restored child run accepts the resident model of its slot and reports the model change
---
## Problem

A nested (sub-agent) session that was recorded on an old model does not restore. `AgentRun.restore` calls Router `restoreSession` with no `acceptingResidentModel`. When the recorded slot holds another model now, the Router throws `modelMismatch`. The child then becomes a failed child, its run is lost, and its history does not replay.

## Work

1. `AgentRun.restore` (Sources/FoundationModelsAgents/Run/AgentRun.swift) gives `acceptingResidentModel: true` to `restoreSession`.
2. The restored `AgentRun` keeps `restored.modelChanges` as `public let modelChanges: [RestoredSession.ModelChange]`. It is empty for a run that was not restored.
3. Update Router to its newest main (f06ec37b). The test support follows the Router API: `ModelLoader.loadLLM` has `kvCache`, and the scripted profile names a `decision` slot.

## Acceptance

- A child recorded on model A restores while model B is resident, replays its history, and reports one model change.
- A child restored on its recorded model reports no model change.
- `swift test` passes.

Request from TestudoApp. After the push, send the sha to TestudoApp and to foundationmodelsrouter-09 (ACPAgent `registerRestoredRun` records the notice). #bug