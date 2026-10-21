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
- actor: claude-code
  id: 01m5f8m8y1sm7esqbsnzgwmpf7
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (commit d785a61): 13 findings confirmed, 1 refuted. AgentCatalogChanges.swift:58,62,65,84,87,90,93,96,99,102,105,108 (code-hygiene/dead-code-swift, assignOnlyProperty, all 12 on the `AgentContent` and `AgentFile` stored properties), AgentsGraph.swift:157 (swift/concurrency).
    - tests: `swift test --filter AgentsGraph` passed 35 tests in 4 suites. Nothing failed. The one warning comes from the mlx-swift bundle in `.build`.
    - acceptance criteria and tests: every box was already ticked, and I checked each against AgentsGraphChangesTests and AgentsGraphTests. Each is met. The accepted deviation stands: the `agentChanges`/`agentsChanges`/`since` aliases are probed through `subscribe` (aliasNamesTheChangesSubscription), not through GraphQLEndpointConformance.
    - AgentsGraph.swift:157: the code compiles as it is, because the outer `try await api.subscribe(...)` already covers the `async` init. The finding asks for `await` at the call itself. Line 138 (`respond`) has the same cause, so fix both call sites.
    - dead-code findings: the properties are read only through the synthesized `Equatable` `==`, and the analyzer does not count that as a read. The fix has to make the analyzer see a read, for example a hand-written comparison or a compared tuple or array of values. Don't drop the findings.
    - concurrency of AgentRegistry, the reviewer's own reading (these are not engine findings):
      - No deadlock. Nothing is awaited while the `generation` Mutex is held. `enqueue` yields into an unbounded AsyncStream and does not block. The feed task holds only the stream and the ChangeLog, not the Mutex or the feed. The feed outlives every `swapIn`, because CurrentBuild owns it and `swapIn` runs on a CurrentBuild that is still referenced.
      - No ordering race between concurrent builds. The diff is taken against `current` under the lock, and `enqueue` also runs under the lock. A build with a lower number is rejected before either runs. The single consumer appends in yield order.
      - The cursor-then-catalog read in `AgentsGraphContext(reading:)` is sound. Each change up to the cursor was appended after its swap, so a client can see a change again but cannot miss one.
      - `onReload` comes before the log append: `publish` runs under the lock, and the append happens later on the feed task. A host that reacts to an `onReload` value by reading `cursor` can still see the earlier cursor. It then gets that change again, but loses nothing. The docs of `onReload`/`swapIn` do not say this.
      - Cancellation: `for await _ in appended {}` returns early when the reloading task is cancelled. `reload()` then returns normally before its entry is in the log. The append still happens. The `reload()` doc says "returns after its change is in the change log", and that does not hold when the task is cancelled.
      - `AgentCatalogChanges.change` runs under the Mutex. It builds an `AgentsGraphAgent`, the diagnostics and an `AgentFile` for every id of both catalogs, so `catalog()`, `isLoaded` and `loadedCatalog()` wait for the whole diff on every swap.
    - next: an implementer clears the 13 open findings, then `/review ^20mv6d3` again.
  timestamp: 2026-10-21T12:57:53.857141+00:00
- actor: claude-code
  id: 01m5f8mx1gn9e2qp1cn9gkf9k7
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 12 files (ChangeLog in CurrentBuild, cursor, changes(after:), AgentChange)
    - test: green — swift test x2, 663 tests in 92 suites, 0 warnings
    - commit: d785a61
    - review: findings — AgentCatalogChanges.swift:58,62,65,84,87,90,93,96,99,102,105,108 (dead-code-swift); AgentsGraph.swift:157 (swift/concurrency)
  timestamp: 2026-10-21T12:58:14.448166+00:00
- actor: claude-code
  id: 01m5f8y05hn2g45sn44891yyws
  text: |-
    Fix pass for the 13 review findings plus the two doc promises from the reviewer's concurrency notes:
    - dead-code-swift (12): `AgentContent` and `AgentFile` in AgentCatalogChanges.swift now have an explicit `static func ==` that reads each stored property. No `// periphery:ignore` marker was used.
    - swift/concurrency: `execute` and `subscribe` in AgentsGraph.swift now do `let context = await AgentsGraphContext(reading: build)` before they call `api.respond`/`api.subscribe`.
    - Cancellation (the reviewer's note): `CurrentBuild.swapIn` now waits through `Self.wait(for:)`, which is `await Task { for await _ in appended {} }.value`. An awaited unstructured task does not get the caller's cancellation, so `reload()` returns after its change is in the log even on a cancelled task. This matches the doc. The `reload()` and `swapIn` docs now state this. New test `aCancelledReloadReturnsAfterItsChangeIsInTheLog` uses a new test-support `CancellingMarketplaceProvider`: its `marketplaceLayers()` cancels the reloading task after the build's `checkCancellation`. ChangesFixture.make now takes an optional `marketplaces:`.
      - What did not work: the first version of the test read the cursor through the endpoint (`fixture.cursor()`) from the test task after awaiting the reload task. That passed with the bug present, because the GraphQL call had enough awaits for the feed task to append first. The working test reads `changeLog.cursor` inside the reloading task right after `reload()`. It went RED as expected (the cursor was unchanged, `...:1` == `...:1`), then GREEN after the fix. The RED depends on scheduling and is not fully deterministic. The GREEN is deterministic.
    - onReload ordering: the docs of `onReload` (AgentRegistry+Reload.swift), of the `Query.cursor` resolver (AgentsGraphSchema.swift), of the AgentsGraph type and of `swapIn` now say that onReload publishes before the log has the change. A cursor read at once can come before the change, and the client then gets that change again. Duplicates can happen, losses cannot. The schema description text is unchanged, so the golden is unchanged.
  timestamp: 2026-10-21T13:03:12.561269+00:00
- actor: claude-code
  id: 01m5f8y42jjb72n90kfraktjxk
  text: |-
    ### implement — changed
    - evidence: `swift test` (sources touched to force a recompile): 664 tests in 92 suites passed, 0 failures. The only warning line is the existing SwiftPM "missing creator ... mlx-swift_Cmlx.bundle" line from the dependency. New test aCancelledReloadReturnsAfterItsChangeIsInTheLog went RED, then GREEN. 13/13 findings checked. Files: Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift, Sources/FoundationModelsAgents/Graph/AgentsGraph.swift, Sources/FoundationModelsAgents/Graph/AgentsGraphSchema.swift, Sources/FoundationModelsAgents/Registry/AgentRegistry.swift, Sources/FoundationModelsAgents/Registry/AgentRegistry+Reload.swift, Tests/FoundationModelsAgentsTests/AgentsGraphChangesTests.swift, Tests/FoundationModelsAgentsTests/Support/CancellingMarketplaceProvider.swift (new)
    - next: /review ^20mv6d3
  timestamp: 2026-10-21T13:03:16.562449+00:00
- actor: claude-code
  id: 01m5f931af8k9ycm50qt0z6jrb
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` complete, no package warnings. `swift test` x2: 664 tests in 92 suites passed, 0 failed, 0 skipped, both runs. `swift test --filter AgentsGraphChangesTests` x5: 15 tests passed each run, no flakiness.
    - only warning seen: SwiftPM `missing creator for mutated node: .../mlx-swift_Cmlx.bundle/Contents/MacOS`, which comes from the mlx-swift dependency's bundle in the build system, not from a source file of this package.
    - no files changed by this step.
    - next: review/commit
  timestamp: 2026-10-21T13:05:57.583765+00:00
- actor: claude-code
  id: 01m5f9cpefspbjtwga9v2mfbwh
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (b44eeb5): 1 finding (1 confirmed, 0 refuted) — Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:143 `swift/access-control`. All 13 prior findings are fixed: the explicit `==` on AgentContent reads agent/file/diagnostics (3 of 3 stored properties), and on AgentFile it reads path/kind/body/compactionPrompt/maxTurns/tools/disallowedTools/skills/unknownFields (9 of 9). AgentsGraph execute/subscribe now `await AgentsGraphContext(reading:)`. The detached wait in swapIn cannot leak or deadlock: the CurrentBuild that runs swapIn keeps changeFeed alive, so the feed deinit (the one path that cancels the appender) cannot run while a waiter waits. `ChangeLog.append` does not throw, so each queued Pending gets `appended.finish()`. A `.terminated` yield finishes the signal at once. The unstructured Task holds only the stream and ends when the stream ends.
    - conflict check: `private static func ==` on a file-scope private Equatable struct compiles and runs under swiftc -swift-version 6 (scratchpad probe), so the finding is not a conflict.
    - scope note: the same cause is the `==` of AgentContent (AgentCatalogChanges.swift:86). Fix both so the whole file is clear.
    - next: implement the finding, then re-run `/review 01M5F23ZX7EBZN1MJFY20MV6D3 <new sha>`.
  timestamp: 2026-10-21T13:11:14.127059+00:00
- actor: claude-code
  id: 01m5f9d77vcypzw0wdz3s6r09n
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 7 files (explicit ==, awaited context, cancellation-safe reload, docs)
    - test: green — swift test x2, 664 tests; AgentsGraphChangesTests x5, no flakiness
    - commit: b44eeb5
    - review: findings — Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:143 (same cause :86; == of a private struct must be private)
  timestamp: 2026-10-21T13:11:31.323046+00:00
- actor: claude-code
  id: 01m5f9j3xzyy1s30t160y6wyc5
  text: |-
    Fix pass for the `swift/access-control` finding (AgentCatalogChanges.swift `==` of a private struct must be `private`), applied to the cause in every private/fileprivate type of the AG-8c files:
    - AgentCatalogChanges.swift: `AgentContent.==` and `AgentFile.==` are `private static func ==`. Each stored property of both structs is read only by the type's own `==`, so it is `private let` now (3 + 9). The two inits are called from a sibling type in the file (`AgentCatalogChanges.contents` calls `AgentContent.init`; `AgentContent.init` calls `AgentFile.init`), so `private` would not compile there; they are `fileprivate init`, the narrowest level that compiles.
    - AgentChangeFeed.swift `Pending` (private, nested): `change`/`appended` are read by the enclosing `AgentChangeFeed` (the feed task and `enqueue` via the memberwise init), so they are `fileprivate let`.
    - AgentRegistry+Reload.swift `Watch`/`Following` (private, nested in AgentReloadLoop): members are read by AgentReloadLoop (`deinit`, `watch(roots:)`, `follow`), so `fileprivate let`. `Phase` is an enum with cases only (no access modifier applies).
    - AgentRegistry.swift `Generation` (fileprivate, nested): `empty`, `number`, `marketplaceLayers`, `catalog`, `read(...)` are used by AgentRegistry and CurrentBuild in the file, so `fileprivate`.
    - No behavior change, so no new test (access modifiers only); the compiler is the check.
  timestamp: 2026-10-21T13:14:11.775272+00:00
- actor: claude-code
  id: 01m5f9j6vyk6scv4pzdjpr1ck1
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` clean (no compiler warning; only the existing SwiftPM mlx-swift_Cmlx "missing creator" line from the dependency); `swift test`: 664 tests in 92 suites passed, 0 failures. 1/1 open finding checked (AgentCatalogChanges.swift:143, same cause :86). Files: Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift, Sources/FoundationModelsAgents/Graph/AgentChangeFeed.swift, Sources/FoundationModelsAgents/Registry/AgentRegistry.swift, Sources/FoundationModelsAgents/Registry/AgentRegistry+Reload.swift
    - next: /review ^20mv6d3
  timestamp: 2026-10-21T13:14:14.782937+00:00
- actor: claude-code
  id: 01m5f9mqhkbbfqna1sqdw87cev
  text: |-
    ### test — green
    - evidence: swift build --build-tests (Build complete, forced recompile of Sources/FoundationModelsAgents/Graph and Registry: 0 warnings from this package); swift test — 664 tests in 92 suites passed, 0 failed, 0 skipped.
    - note: the only build line containing "warning" is SwiftPM's "missing creator for mutated node: .../mlx-swift_Cmlx.bundle/Contents/MacOS", emitted by the mlx-swift dependency's bundle in the build graph, not by this package's sources.
    - next: review/commit (nothing committed by this step)
  timestamp: 2026-10-21T13:15:37.395258+00:00
- actor: claude-code
  id: 01m5f9zcatjx6vpaqptb0trm6k
  text: |-
    ### review — stuck
    - evidence: review sha HEAD~1..HEAD (a7600ad): 9 findings (9 confirmed, 1 refuted). The prior 08:06 item at AgentCatalogChanges.swift:143 is applied as written (`private static func ==`). The new items are AgentCatalogChanges.swift:72, :86, :124, :143; AgentChangeFeed.swift:22, :26; AgentRegistry+Reload.swift:54, :57, :67. The seven swift/access-control items require `private` on members that are used outside their struct, and swiftc rejects that ("inaccessible due to 'private' protection level"). This is a true conflict: the rule requires code that cannot compile.
    - next: a person corrects the swift/access-control rule (a member of a file-scope private type, or of a private nested type, may be fileprivate when it is used outside the struct). The dead-code-swift items at :86 and :143 stay open: the private `==` operators are not the Equatable witness, so the compiler's synthesized `==` runs and the hand-written ones are unused.
  timestamp: 2026-10-21T13:21:26.362169+00:00
- actor: claude-code
  id: 01m5fa02478bn5twn2ha0d0xeh
  text: |-
    ### finish iteration 3 — stuck
    - implement: changed — access levels narrowed in 4 files
    - test: green — swift test, 664 tests in 92 suites, 0 package warnings
    - commit: a7600ad (local, not pushed)
    - review: stuck — 7 swift/access-control findings (AgentCatalogChanges.swift:72,124; AgentChangeFeed.swift:22,26; AgentRegistry+Reload.swift:54,57,67) require `private` on members used outside their struct, which does not compile. 2 dead-code findings (:86, :143): a `private ==` on a private Equatable struct is not the witness, so the synthesized == is used and the hand-written one is dead.
    - Needs a human decision on the access-control rule (or a structural change such as making these helper types internal/nested) before the loop can continue. Commits b44eeb5 and a7600ad are local only.
  timestamp: 2026-10-21T13:21:48.679672+00:00
- actor: claude-code
  id: 01m5fcd6t29g5shsyp1tc4tt8c
  text: |-
    ### review overridden by the user
    The user overrode the stuck review. The 7 swift/access-control findings (they ask for `private`, which does not compile) and the 2 dead-code findings on the private `==` stay open as known issues. The task moves to done and is pushed. Tests: 664 passing.
  timestamp: 2026-10-21T14:03:56.610274+00:00
depends_on:
- 01M5F23E7S4NJTPNFFVB8W613Y
position_column: done
position_ordinal: f680
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

## Review Findings (2026-10-21 07:51)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 7 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 3 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md` — no validator matches this file
> - `Tests/Fixtures/agents.graphql` — no validator matches this file

- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:58` `code-hygiene/dead-code-swift` — var.instance `agent` is assignOnlyProperty.
- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:62` `code-hygiene/dead-code-swift` — var.instance `file` is assignOnlyProperty.
- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:65` `code-hygiene/dead-code-swift` — var.instance `diagnostics` is assignOnlyProperty.
- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:84` `code-hygiene/dead-code-swift` — var.instance `path` is assignOnlyProperty.
- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:87` `code-hygiene/dead-code-swift` — var.instance `kind` is assignOnlyProperty.
- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:90` `code-hygiene/dead-code-swift` — var.instance `body` is assignOnlyProperty.
- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:93` `code-hygiene/dead-code-swift` — var.instance `compactionPrompt` is assignOnlyProperty.
- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:96` `code-hygiene/dead-code-swift` — var.instance `maxTurns` is assignOnlyProperty.
- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:99` `code-hygiene/dead-code-swift` — var.instance `tools` is assignOnlyProperty.
- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:102` `code-hygiene/dead-code-swift` — var.instance `disallowedTools` is assignOnlyProperty.
- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:105` `code-hygiene/dead-code-swift` — var.instance `skills` is assignOnlyProperty.
- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:108` `code-hygiene/dead-code-swift` — var.instance `unknownFields` is assignOnlyProperty.
- [x] `Sources/FoundationModelsAgents/Graph/AgentsGraph.swift:157` `swift/concurrency` — Async initializer `AgentsGraphContext(reading:)` is called without `await`. Same issue as line 138: the initializer is declared `async` and must be awaited when called in the `subscribe` function. Change `context: AgentsGraphContext(reading: build)` to `context: await AgentsGraphContext(reading: build)`.

## Review Findings (2026-10-21 08:06)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:143` `swift/access-control` — The `==` operator for a `private struct` must be marked `private` to match the type's access level. An implicit `internal` access level on a member of a `private` type exceeds the type's visibility. Mark the function `private`: `private static func == (lhs: AgentFile, rhs: AgentFile) -> Bool {`.

## Review Findings (2026-10-21 08:15)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [ ] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:72` `swift/access-control` — Initializer of a private struct is exposed with fileprivate access level, making it wider than the containing type. The initializer should be private to match the struct's access level and conform to the stated goal of 'members are no wider than their type'. Change `fileprivate init` to `private init` on line 72.
- [ ] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:86` `code-hygiene/dead-code-swift` — function.operator.infix `==(_:_:)` is unused.
- [ ] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:124` `swift/access-control` — Initializer of a private struct is exposed with fileprivate access level, making it wider than the containing type. Change `fileprivate init` to `private init` on line 124.
- [ ] `Sources/FoundationModelsAgents/Graph/AgentCatalogChanges.swift:143` `code-hygiene/dead-code-swift` — function.operator.infix `==(_:_:)` is unused.
- [ ] `Sources/FoundationModelsAgents/Graph/AgentChangeFeed.swift:22` `swift/access-control` — Property of a private struct is exposed with fileprivate access level, making it wider than the containing type. The property should be private to match the struct's access level and conform to the stated goal of 'members are no wider than their type'. Change `fileprivate let change` to `private let change` on line 22.
- [ ] `Sources/FoundationModelsAgents/Graph/AgentChangeFeed.swift:26` `swift/access-control` — Property of a private struct is exposed with fileprivate access level, making it wider than the containing type. The property should be private to match the struct's access level. Change `fileprivate let appended` to `private let appended` on line 26.
- [ ] `Sources/FoundationModelsAgents/Registry/AgentRegistry+Reload.swift:54` `swift/access-control` — Property of a private struct is exposed with fileprivate access level, making it wider than the containing type. The property should be private to match the struct's access level and conform to the stated goal. Change `fileprivate let roots` to `private let roots` on line 54.
- [ ] `Sources/FoundationModelsAgents/Registry/AgentRegistry+Reload.swift:57` `swift/access-control` — Property of a private struct is exposed with fileprivate access level, making it wider than the containing type. Change `fileprivate let watcher` to `private let watcher` on line 57.
- [ ] `Sources/FoundationModelsAgents/Registry/AgentRegistry+Reload.swift:67` `swift/access-control` — Property of a private struct is exposed with fileprivate access level, making it wider than the containing type. Change `fileprivate let updatesTask` to `private let updatesTask` on line 67.

## Blocker: swift/access-control conflicts with code that compiles (2026-10-21 08:15)

The seven `swift/access-control` items in the 08:15 section (AgentCatalogChanges.swift:72, :124; AgentChangeFeed.swift:22, :26; AgentRegistry+Reload.swift:54, :57, :67) require code that cannot compile. A `private` member of a struct is visible only inside that struct and its same-file extensions — not in the enclosing type or the rest of the file. Each flagged member is used from outside its struct:
- `AgentContent.init(id:in:)` is called from `enum AgentCatalogChanges` (AgentCatalogChanges.swift, `AgentContent(id: id, in: catalog)`).
- `AgentFile.init(_:)` is called from `AgentContent.init` (`definition.map(AgentFile.init)`).
- `Pending.change` / `Pending.appended` are read by `AgentChangeFeed` (`pending.change`, `pending.appended.finish()`).
- `Watch.roots` / `Watch.watcher` and `Following.updatesTask` are read by `AgentReloadLoop` (`current?.roots`, `current?.watcher.stop()`, `following.updatesTask?.cancel()`).

Checked with `swiftc -typecheck` on a minimal probe: `private init` / `private let` in this shape fails with "initializer is inaccessible due to 'private' protection level" and "'change' is inaccessible due to 'private' protection level". `fileprivate` is the narrowest level that compiles, and for a private type at file scope it equals the type's effective access. A person must correct the `swift/access-control` rule; the task is stuck on these seven items.

Note on the two `code-hygiene/dead-code-swift` items (:86, :143): these are not part of the conflict. A probe shows that a `private static func ==` on a file-scope `private` Equatable struct is not the conformance witness — the compiler synthesizes `==` and the hand-written operator never runs. The 08:06 item (`private ==` at :143) is applied as written, and that change is what makes both operators dead.