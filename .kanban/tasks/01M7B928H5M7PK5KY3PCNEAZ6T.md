---
assignees:
- claude-code
position_column: doing
position_ordinal: '80'
title: 'agents endpoint: the iCloud conflict versions of each agent (TestudoApp ^3ysdajb, D154)'
---
## What
The `agents` GraphQL endpoint gives, for each agent, the unresolved iCloud conflict versions of its AGENT.md. The iPad/iPhone client (a pure ACP client) then reads the same data as the Mac app (D154 rule 1). Today the app finds the versions itself with NSFileVersion (D88 (h)).

- New file `Sources/FoundationModelsAgents/Registry/AgentConflictVersions.swift`:
  - `public struct AgentConflictVersion` (`id`, `deviceName`, `modificationDate`).
  - `public protocol AgentConflictVersionSource`: `conflictVersions(of:)` reads the versions of one file. `changes(under:)` gives a value when a version comes or is resolved under a root.
  - `public struct FileVersionConflictSource`: the NSFileVersion source, with an NSFilePresenter on each root for the change signal. The id is the archived `persistentIdentifier` in base64, thus the host resolves it with `NSFileVersion(itemAt:forPersistentIdentifier:)`.
- `AgentRegistry` inits get `conflictVersions:` (default `FileVersionConflictSource()`). Each build reads the versions of the winning file of each agent into `AgentCatalog.conflicts(of:)`.
- `AgentReloadLoop.watch(roots:)` also follows `changes(under:)` of the source, and each value gives a reload. `stopWatching()` stops it.
- Schema: type `AgentConflict { id: ID!, deviceName: String, modifiedAt: DateTime }` and field `Agent.conflicts: [AgentConflict!]!`. A change of the conflicts makes the agent id `changed` in `AgentChange`.

## Acceptance Criteria
- [ ] `agents { id conflicts { id deviceName modifiedAt } }` gives the versions of the fake source.
- [ ] A new version or a resolve from the source gives one `AgentChange` with the id in `changed`.
- [ ] `stopWatching()` stops the follow of the source.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentConflictVersionTests.swift`: a fake source gives a conflict → the endpoint lists it and the subscription sends an event; a resolve → the conflict goes and an event comes.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1