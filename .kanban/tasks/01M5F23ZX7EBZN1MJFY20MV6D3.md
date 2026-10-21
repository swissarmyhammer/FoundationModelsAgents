---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f3wprdg40ahr4mharejx84
  text: |-
    Unblocked: EXTRAS-10 is on FoundationModelsExtras origin/main (code f126153, tip 11ffe56). First step: `swift package update FoundationModelsExtras` and adopt that commit.

    API (Sources/FoundationModelsExtras/GraphQL/):
    - `actor ChangeLog<Event>`: `init(capacity: Int = 1024)`, `append(_:)`, `cursor`, `changes(after:where:)`. Stream elements are `ChangeLogEntry<Event> { cursor: String, at: Date, event }`. `changes(after: nil)` gives only live events.
    - IDChange.swift: use `ChangedIDs` (added/changed/removed ids) as the Event, and `IDChange` as the shared `<Noun>Change` shape (at as DateTime). Check how `IDChange` names its GraphQL type against the `AgentChange` name rule 9 wants.
    - Codes: `GraphQLToolkitError.notFound(kind:id:)` and `.resyncRequired(reason:)`.

    Behaviour to test:
    - A subscription stream that throws a coded error sends one final `{"errors":[…]}` with extensions.code, then ends normally.
    - A subscriber more than `capacity` events behind gets RESYNC_REQUIRED.

    EXTRAS-11 (conformance checks) has not landed; use the current GraphQLEndpointConformance until it does.
  timestamp: 2026-10-21T11:35:07.277045+00:00
- actor: claude-code
  id: 01m5f7k5yt0rsameya9fz8b8t1
  text: |-
    Research (implement):
    - Extras resolved at bd34b20 (after 9c47e10): `ChangeLog`, `ChangedIDs`, `IDChange` (mapped with `Type(IDChange.self, as: "AgentChange")`, ids are ToolkitID → `[ID!]!`), `GraphQLConventionRule.changes` checks `changes(after: String)`, the event fields and `Query.cursor: String!`.
    - Reference: FoundationModelsSkills SkillChangeFeed/SkillsGraph. Its feed appends from an `onReload` task, so `reload()` returns before the event is in the log, and its tests poll the cursor with a timeout. That is a wall-clock wait, which this task forbids.
    - Design here: the ChangeLog lives in `AgentRegistry.CurrentBuild` (the one shared build state, so `AgentsGraph(registry:)`, `registry.agentsGraph()` and each AgentsTool read one log; the public init stays and shares the log). `swapIn` diffs the old and new catalog UNDER the swap lock (the same lock that publishes onReload, so every reload path — watcher, layerUpdates, reload() — feeds it in swap order) and queues the event to one feed task that appends in order. `build()` becomes async and waits until its event is in the log, so `try await registry.reload()` is the test sync point (no poll, no timeout).
    - Query/cursor consistency: each call takes one snapshot: the log cursor first, then the catalog. An event is appended only after its catalog swapped in, so a cursor never runs ahead of the catalog it is read with (a change can be seen twice, never missed).
    - Diff content per id: the Agent object the endpoint gives (keys, layer, marketplace, diagnostics) plus the file (path, body, the keys the Agent type does not give). `layerIndex` is left out: a new marketplace layer below shifts every index without changing an agent. An id with diagnostics only (no definition before or after) is `changed` when its diagnostics change.
    - The conformance alias probe runs through `execute`, not `subscribe`; the `agentChanges` alias is also tested through `subscribe`.
  timestamp: 2026-10-21T12:39:49.466089+00:00
- actor: claude-code
  id: 01m5f83x9sgacxk380jqc8gwdz
  text: |-
    Implementation landed (not committed):
    - `AgentRegistry.CurrentBuild` now owns the one `ChangeLog<ChangedIDs>` of the registry (`changeLogCapacity = 1024`) and an `AgentChangeFeed`. `swapIn` is async: under the swap lock it diffs the old and new catalog (`AgentCatalogChanges.change(from:to:)`), swaps, publishes onReload, and queues the change; it then waits until the feed task appended it. `build()` (load/reload) is async-awaits that, so `try await registry.reload()` returns with the change in the log. Every onReload source (watcher, layerUpdates, explicit reload) goes through swapIn, so the feed sees each reload in swap order with no separate onReload subscriber and no seed race.
    - `AgentsGraphContext(reading:)` reads the log cursor, then the catalog, once per call; every query field (incl. `Query.cursor`) reads that snapshot. Resolver now holds only the change log.
    - Schema: `AgentChange` = `Type(IDChange.self, as: "AgentChange")`, `Query.cursor: String!`, `Subscription.changes(after: String): AgentChange!`. Aliases `agentChanges`/`agentsChanges` → `changes`, `since` → `after`. Golden re-recorded.
    - `AgentsGraph(registry:)` stays public: it reads `registry.currentBuild`, so it shares the registry's log and cursor (tested next to two AgentsTool copies).
    - Diff content per id: `AgentsGraphAgent` (now Equatable, plus the nested types) + a private `AgentFile` (path, kind, body, compactionPrompt, maxTurns, tools, disallowedTools, skills, unknownFields) + `AgentsGraphDiagnostic.naming(id, in:)` (new helper, also used by `AgentsGraphAgent`). Provenance `layerIndex` is not compared.
    - Deviation: `GraphQLAliasProbe` runs through `execute`; a `subscription { agentChanges { cursor } }` probe gives "Expected source type ChangeLogEntry<ChangedIDs> but got AgentsGraphResolver" (tried). The conformance call has no exception and keeps the `agent(name:)` probe; `agentChanges`/`agentsChanges` + `since` are probed via `subscribe` in AgentsGraphChangesTests (same split as FoundationModelsSkills). If the conformance kit should probe subscriptions, that is an Extras change.
    - Package.resolved is git-ignored here; local resolve is Extras bd34b20.
  timestamp: 2026-10-21T12:48:57.657015+00:00
- actor: claude-code
  id: 01m5f843b38nr1qr556g5tzc1c
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` clean (no compiler warning; only the SwiftPM mlx-swift_Cmlx "missing creator" build-graph line from the dependency); `swift test` 663 tests in 92 suites passed. New suite AgentsGraphChangesTests (15 tests, 16 cases) watched RED (compile: no `CurrentBuild.changeLog`/`changeLogCapacity`) then GREEN; theSchemaMatchesTheGoldenFile RED then golden re-recorded; theEndpointConforms with no exception GREEN. Files: Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift (new), Sources/FoundationModelsAgents/Graph/AgentChangeFeed.swift (new), Sources/FoundationModelsAgents/Graph/AgentsGraph.swift, Sources/FoundationModelsAgents/Graph/AgentsGraphPort.swift, Sources/FoundationModelsAgents/Graph/AgentsGraphSchema.swift, Sources/FoundationModelsAgents/Graph/AgentsGraphTypes.swift, Sources/FoundationModelsAgents/Registry/AgentRegistry.swift, Tests/FoundationModelsAgentsTests/AgentsGraphChangesTests.swift (new), Tests/FoundationModelsAgentsTests/AgentsGraphTests.swift, Tests/Fixtures/agents.graphql, README.md, Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md
    - note: the `agentChanges` alias probe is a subscribe test, not a `GraphQLAliasProbe` (the kit probes through `execute`); see the previous comment.
    - next: /review
  timestamp: 2026-10-21T12:49:03.843956+00:00
- actor: claude-code
  id: 01m5f88a3a95hnmvfhqpwrpc74
  text: |-
    ### test — green
    - evidence: swift build --build-tests (forced full recompile of package sources and tests by touching them): 0 package warnings, 0 errors. swift test run 1: 663 tests in 92 suites passed, 0 failures, 0 skipped. swift test run 2 (requested for timing sensitivity): 663 tests in 92 suites passed. No flakiness observed in the AG-8c subscription/reload tests across the two runs.
    - note: the only build output warning is the SwiftPM "missing creator for mutated node ... mlx-swift_Cmlx.bundle" line, from the mlx-swift dependency bundle, not package source.
    - next: review
  timestamp: 2026-10-21T12:51:21.834035+00:00
depends_on:
- 01M5F23E7S4NJTPNFFVB8W613Y
position_column: doing
position_ordinal: '80'
title: 'AG-8c AgentsGraph: changes(after:) subscription and opaque cursor from the ChangeLog'
---
## What
EXTRAS-9 rule 9 (rev 2, D67) for the `agents` endpoint:
- `Subscription.changes(after: String): AgentChange!`. `AgentChange` has `cursor: String!`, `at: DateTime!`, `added: [ID!]!`, `changed: [ID!]!`, `removed: [ID!]!`. One event per reload. The client queries `agent(id:)` again for each added or changed id; a removed id needs no query, and there is no tombstone type.
- `Query.cursor: String!`: the opaque cursor of the catalog that a query reads. Query and cursor read one generation, so a client that reads `agents` then `changes(after: cursor)` misses no change.
- `ChangeLog` has an epoch per instance. A cursor from another epoch (for example, before a process restart), a cursor that is too old for the buffer, or a cursor after the newest event gives `RESYNC_REQUIRED`. No `after` starts from now.
- Feed: one `ChangeLog<AgentChange>` per `AgentRegistry` (rule 1: the endpoint and its ChangeLog are made once per port, not per `AgentsTool` copy, so every copy gives the same cursor). Feed it from `onReload` (the dotfolder watcher, `layerUpdates`, and an explicit `reload()`, so AG-9 writes also show). Diff consecutive catalogs by id and by the content of each definition (file content/modification, frontmatter, layer) into added/changed/removed. A reload with no difference appends nothing. A diagnostics-only change counts as `changed` for the agent it names.
- Use `ChangeLog.changes(after:where:)` only if a per-subscriber filter is needed (none is expected: the scope is the session folder and the host checks the folder).
- Alias tables: `agentChanges`, `agentsChanges` → `changes`; `since` → `after`.
- Remove the rule-9 exception from the conformance test of AG-8a.

## Acceptance criteria
- [x] Adding, editing and removing `<name>/AGENT.md` in a watched layer each give one `AgentChange`, with that id in `added`, `changed` or `removed`, and a new cursor.
- [x] One reload that changes several agents gives one event with all of their ids.
- [x] `cursor` equals the cursor of the last event; `changes(after: cursor)` gives only later events.
- [x] A cursor from another epoch, one that is too old, or one after the newest event gives `RESYNC_REQUIRED`.
- [x] A reload with no difference gives no event.
- [x] Two `AgentsTool` copies over one registry give the same cursor.

## Tests
- [x] `GraphQLEndpointConformance.problems` is empty with no exception, with an alias probe for `agentChanges`. (The conformance probe runs through `execute`, which cannot start a subscription, so the conformance call keeps the `agent(name:)` probe and `agentChanges`/`agentsChanges`/`since` are probed through `subscribe` in AgentsGraphChangesTests.)
- [x] The schema golden is updated.
- [x] Subscription tests over `TemporaryLayer` with explicit `reload()` (no wall-clock waits; each wait also ends on failure, test rule T1). #AG-8