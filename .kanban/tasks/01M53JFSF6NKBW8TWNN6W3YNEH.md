---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: 'Known exceptions to test rule T1: waits with no failure event'
---
These waits stay after ^4m8q28x. Each one has no failure event that the test can use today. No `.timeLimit`, sleep, poll or retry was added.

## Reload waits (14): the watcher or a background reload gives the only event
- AgentRegistryReloadTests.swift:119 — a `layerUpdates` value causes the reload in a background task; no failure event comes when that reload fails.
- AgentRegistryReloadTests.swift:135, 149–150, 164 — real file system event (add, change, remove).
- AgentRegistryReloadTests.swift:192, 196 — real file system events of the burst.
- AgentRegistryReloadTests.swift:216 — the end of the stream after the release is the subject of the test.
- AgentFolderWatchTests.swift:24, 43 — real file system event in an agent folder, and the move of the placeholder.
- MarketplaceEndToEndTests.swift:314 — the store update causes the reload through `layerUpdates` in a background task.
- SlashCommandTests.swift:156 — `commandUpdates` gets its values from a separate task; the harness keeps the registry.
- SkillsToolSharingTests.swift:88 — the `SkillsRegistry` watcher is in FoundationModelsSkills, with no public `reload()` and no way to give an event by hand.
- FindAgentsTests.swift:204 — the search index updates in a separate task.
- IntegrationTests/.../LiveCommandTests.swift:106 — live edit through the real watcher.

## Other waits with no run before the wait (9)
- AgentRunnerTests.swift:198 — the run comes from `async let started`.
- SendAgentTests.swift:189 — the root answer is an `async let`; there is no run.
- AgentSchedulingTests+Setup.swift:150, 193, 217 — setup gates; the start is held in the probe or in `async let hostStart`.
- AgentSchedulingTests+CallingRun.swift:88, CancelAllFinalMessageTests.swift:163 — the child run can come into the index after its pending start.
- NestedRunTests+Messages.swift (message in the task turn) — the child gate wait is plain, for the same reason.
- RunEventObserverTests.swift (the tool-body gate) — the tool body holds on the gate; while it holds, no other event can come.

## Possible later items (not started)
- Extras: a public or package way to give a watch-source factory to `DotfolderWatcher` (commit 6959dd7 keeps `OpenWatchSource`, `WatchSourceHandlers` and `DebounceTimer` internal). Agents then needs a seam to give that watcher to `AgentRegistry` / `AgentReloadLoop`.
- FoundationModelsSkills: the same seam for `SkillsRegistry`, or a public `reload()`. #elicitation-check #waits-on-extras