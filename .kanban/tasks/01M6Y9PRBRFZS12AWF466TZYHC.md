---
assignees:
- claude-code
position_column: done
position_ordinal: fe80
title: 'start agent: treat workingDirectory "nil"/"null"/"none"/"undefined" as no folder, refuse a folder that does not exist'
---
Forgiving-tools fix (from a FoundationModelsACPAgent session; SWE-bench run dotask24, django__django-14017, and nokanban24b, django__django-14411).

A model called `agents {"op":"start agent", ..., "workingDirectory":"nil"}`. `AgentsToolContext.requestedDirectory(at:)` (Sources/FoundationModelsAgents/Tool/AgentsToolContext.swift:140) resolved `nil` against the base folder, so the child got `<parent>/nil`, a folder that does not exist. The Hooks snapshot store then failed with `workingDirectoryMismatch`, and the child ran with no snapshots.

## Fix
1. `nil`, `null`, `none`, `undefined` (case-insensitive, trimmed) name no folder: `requestedDirectory(at:)` returns nil, the run gets the default folder.
2. `start agent` refuses a resolved folder that does not exist: no run, a corrective that names the resolved path and says to leave `workingDirectory` out to use your own folder.
3. Clearer `@Guide` of `StartAgent.workingDirectory`: omit the field; the value must be an existing folder, never the text nil.

## Acceptance
- [ ] Test: each placeholder text names no folder (child works in the parent folder).
- [ ] Test: a folder that does not exist gives the corrective with the resolved path, and starts no run.
- [ ] swift test green. #bug