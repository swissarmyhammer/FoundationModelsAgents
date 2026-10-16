---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m52qrv6rqw2awwtg3r55yj2x
  text: 'The app session agreed to the full design of this card (recorded in AG-4 of SwissArmyHammerApp): the optional `agentFolders` input, no iCloud code, the precedence, the fixed id `default` for the root `AGENT.md`, `AgentCatalog.defaultAgent` as the hook, `folderURL` = `<url>`, the root file wins over `<url>/default/`, the later URL wins, partials in `<url>/_partials/`. A project `default` agent can replace the root file.'
  timestamp: 2026-10-16T16:12:24.664675+00:00
- actor: claude-code
  id: 01m52tsevyagscsd7etd9fwz7q
  text: |-
    Research (implement step):
    - The local `Package.resolved` is not tracked (it is in `.gitignore`), and its pins were from 2026-10-11. With those pins the build failed (`SessionOutput`, `UserPresence` not found in Router dc64225). `swift package update` moved the pins to Router 24e1a62, Extras 782b8d3, Skills cf1ce54. Then `swift build --build-tests` is green. The Extras APIs that this card uses (`DotfolderStack`, `StenciledDotfolderStack`, `FrontmatterDocumentStack`, `DotfolderWatcher`) have no breaking change in that range (only a new optional `includeResolver:` on `StenciledDotfolderStack.init`).
    - `DotfolderStack.Source` has only `defaults`, `user`, `project`, `marketplace`. An agent-folder layer uses `.user`: it is not trusted, and it is not a marketplace layer.
    - `StenciledDotfolderStack` scopes the partials of a local document to ALL non-marketplace layers of its base stack. Thus the renderer must give an agent-folder document a base stack with only its own layer, and give a dotfolder document a base stack with no agent-folder layer. Else `_partials/` of one source leaks into the other.
    - The combined `DotfolderStack` view cannot serve two path layouts. The builder must read each document from a stack of its winning layer only.
    - `LoadingBoundaryTests` forbids `FileManager`, `contentsOfDirectory`, `String(contentsOf`, `resourceValues` in the library. Thus the placeholder check uses `DotfolderStack.urls(_:)` (it lists hidden files too). `NSFileCoordinator` is not forbidden.
    - `DotfolderWatcher` watches each root recursively, and each directory source sees `.write/.delete/.rename`. Thus the rename of a placeholder to `AGENT.md` gives one `onChange`.
  timestamp: 2026-10-16T17:05:10.526454+00:00
- actor: claude-code
  id: 01m52vk8h802jvz859299knywh
  text: |-
    Implementation landed (not committed).

    Design as built:
    - `AgentRegistry` has `agentFolders: [URL] = []` on each of the three public inits, and a public `agentFolders` property. `layers` now comes from `AgentCatalogLayer.ordered(...)`: the agent-folder layers go directly below the FIRST `.project` layer of the local layers (a layer that the host puts above project stays above). With no project layer they are the highest layers. Each agent-folder layer has the source `.user` (untrusted, not marketplace).
    - New `AgentDocumentKind` (`agentsFolder` / `agentFolder` / `rootDocument`) on `AgentDefinition` (internal `kind`). It gives the document path, the name rule (`rootDocument` skips the `name` rule: `AgentDefinitionRules.displayNameRules`), and the partial scope.
    - New `AgentLayerScan` scans each layer by itself into `AgentCopy` values. The builder groups the copies by id; the highest copy wins; lower copies give the hidden-copy advisory. Each read is from a single-layer stack of the winner, because the combined view cannot serve two layouts.
    - Agent-folder scan: one `DotfolderStack.urls()` walk (lists hidden files; no `FileManager` in the library, so `LoadingBoundaryTests` stay green). Placeholder rules: a hidden name that holds `AGENT.md` stands for the document (root or `<id>/`); a hidden root file `.<id>.<suffix>` with a valid id stands for the agent folder `<id>`. A not-local winner, or an agent-folder `AGENT.md` that does not read as text, gives one `.skip` with `AgentCatalogBuilder.notLocalMessage` ("the agent document is not local yet; ..."). Known limit of the generic folder rule: a hidden root file like `.env.local` reads as a placeholder of agent `env`.
    - Agent-folder reads go through `NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt:)`.
    - Renderer: an agent-folder document renders with a stack of its own layer only; a dotfolder/marketplace document never sees an agent-folder layer (`registry.localLayers` stays the host layers).
    - Watch: `watchedRoots` adds each agent-folder URL. A test proves that the rename of `.AGENT.md.icloud` to `AGENT.md` gives a new catalog.
    - `AgentCatalogBuilder.documentPath(of:)` was removed (no caller after the renderer change).
    - Guard `NoCloudSyncCodeTests`: no Swift line under `Sources/` may hold `icloud` or `ubiquit` in any letter case (comments included). Docs under `docs/` may name the app's iCloud folder.
  timestamp: 2026-10-16T17:19:16.008253+00:00
- actor: claude-code
  id: 01m52vkcn46344cqm9fvq85jh2
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` clean (0 warnings from the package). New suites RED first (compile failure: no `agentFolders`, no `defaultAgent`), then GREEN: `swift test --filter 'AgentFolder|NoCloudSyncCode'` 26 tests in 7 suites passed. Full suite one time: `swift test` 554 tests in 78 suites passed, 0 failures.
    - files: Sources/FoundationModelsAgents/Definition/AgentDocumentKind.swift (new), Definition/AgentDefinition.swift, Definition/AgentDefinitionRules.swift, Registry/AgentCatalog.swift, Registry/AgentCatalogBuilder.swift, Registry/AgentCatalogLayer.swift (new), Registry/AgentLayerScan.swift (new), Registry/AgentRegistry.swift, Run/AgentBodyRenderer.swift, FoundationModelsAgents.docc/LoadingTheCatalog.md, docs/skills-and-agents.md; Tests: AgentFolderSourceTests.swift, AgentFolderPlaceholderTests.swift, AgentFolderRenderTests.swift, AgentFolderWatchTests.swift, NoCloudSyncCodeTests.swift, Support/AgentFolderFixture.swift (all new).
    - next: /review
  timestamp: 2026-10-16T17:19:20.228148+00:00
- actor: claude-code
  id: 01m52vp4yfm5ph1f4cxwzhh90c
  text: |-
    ### test - stuck
    - evidence: swift test - 554 tests in 78 suites passed, 0 failed, 0 skipped. Build shows 1 warning: "missing creator for mutated node: .build/out/Products/Debug/mlx-swift_Cmlx.bundle/Contents/MacOS".
    - cause: the warning comes from the build system, from the bundle of the mlx-swift dependency. It is not in the sources of this package. I removed the stale bundle and built again. The warning stays.
    - blocker: no code change in this package can remove the warning. A person must decide how to handle it (dependency update or accept).
    - next: person decides on the mlx-swift build warning.
  timestamp: 2026-10-16T17:20:50.639059+00:00
- actor: claude-code
  id: 01m52w0mpkj9f966zhw0s5h5cy
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (commit 0f03c75). Engine: 2 confirmed, 2 refuted. Design check against the task description: 1 more finding (the placeholder rule). 3 open findings: Sources/FoundationModelsAgents/Registry/AgentCatalogBuilder.swift:253, Sources/FoundationModelsAgents/Registry/AgentLayerScan.swift:204, Tests/FoundationModelsAgentsTests/Support/AgentFolderFixture.swift:60.
    - next: implement the 3 findings in the "Review Findings (2026-10-16 12:21)" section, then review again.
  timestamp: 2026-10-16T17:26:34.451786+00:00
- actor: claude-code
  id: 01m52w1amwdrwjfxgmk8xqx3dn
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 17 files (3 new + 6 changed Sources, 2 docs, 6 new test files)
    - test: green — swift test, 554 tests in 78 suites passed, 0 failed, 0 skipped. The only warning is the old SwiftPM line "missing creator for mutated node" for the mlx-swift_Cmlx bundle of a dependency. It was there before this change, as the earlier done tasks record.
    - commit: 0f03c75
    - review: findings — Sources/FoundationModelsAgents/Registry/AgentCatalogBuilder.swift:253, Sources/FoundationModelsAgents/Registry/AgentLayerScan.swift:204, Tests/FoundationModelsAgentsTests/Support/AgentFolderFixture.swift:60
  timestamp: 2026-10-16T17:26:56.924572+00:00
- actor: claude-code
  id: 01m52w60kqbkdgpr48htd4b4a6
  text: |-
    Research for the 3 review findings (implement step, pass 2):
    - Finding 1: `NSFileCoordinator.coordinate(readingItemAt:)` does not fail for a URL that does not exist, an https URL, or a data URL (a probe proved it: the accessor runs and the error stays nil). It fails when a file presenter of the file gives an error from `savePresentedItemChanges(completionHandler:)`: the accessor does not run and the error is that presenter error. A unit test can use a real `NSFilePresenter` that refuses. No test seam in production code is necessary.
    - Finding 2: a name alone cannot tell `.env.local` from a placeholder `.<id>.<suffix>` of a whole folder, and the package must not name the suffix of a sync service (guard `NoCloudSyncCodeTests`). A sync engine keeps each folder and writes a placeholder only for a file. Thus the strict rule is: a hidden root file never stands for an agent folder. Only `.AGENT.md.<suffix>` (exact prefix `.AGENT.md.` and a suffix that is not empty) stands for a document, at the root or directly in `<id>/`. The old rule `name.contains("AGENT.md")` was also too wide (for example `.oldAGENT.md`); the same cause, thus the same fix.
    - Finding 3: the private `agentText` helpers are in `AgentRegistryReloadTests.swift` (`agentText(named:description:)`) and `AgentRegistryMarketplaceTests.swift` (`agentText(named:)`). Both build the same frontmatter as `AgentFolderFixture.agentText(name:body:)`.
  timestamp: 2026-10-16T17:29:30.487806+00:00
- actor: claude-code
  id: 01m52wnghc2w80fmq60nnez0fj
  text: |-
    The 3 review findings are fixed (not committed). All 3 are now `- [x]`.
    - Finding 1 (`swift/error-handling`): `coordinatedRead` now returns `Result<Value?, CoordinatedReadFailure>`. `CoordinatedReadFailure` is a typed `Error` struct with the `reason` text of the coordinator error. The `NSError` stays only as the inout parameter that the `NSFileCoordinator` API requires. A new `readDocument(of:in:at:decodeFailures:)` gives the result. `readWinner` gives one `skip` with `coordinationFailedMessage(_:)` ("the coordinated read of the agent document failed: <reason>"). Thus a failed coordination no longer reads as "not local yet". A new `skip(agent:provenance:message:)` helper builds both skip loads. No other error in the file was dropped.
    - Finding 2 (`design-check/task-description`): `AgentPlaceholderName.folderID(of:)` and `folderPlaceholderCopies` are deleted. A hidden root file never stands for an agent folder, because a sync engine keeps each folder and writes a placeholder only for a file. The same cause was also in `standsForDocument`, which accepted each hidden name that held `AGENT.md`. Now only `.AGENT.md.<suffix>`, with a suffix that is not empty, is a placeholder. The old test `folderPlaceholderGivesOneDiagnostic` tested the removed rule, thus it is replaced.
    - Finding 3 (`reuse/reuse`): `AgentFolderFixture.agentText(name:description:body:)` is now the one source of the text. Its defaults are `AgentFolderFixture.description` and the new `AgentFolderFixture.body`. The private helpers `AgentRegistryReloadTests.agentText(named:description:)` and `AgentRegistryMarketplaceTests.agentText(named:)` now call it. `AgentRegistryMarketplaceTests.agentBody` is now `AgentFolderFixture.body`.
    - Discovery: when a file presenter refuses with a Swift `LocalizedError`, the coordinator does not keep its `errorDescription`. You get "The operation couldn't be completed". The test presenter uses `CustomNSError` with `NSLocalizedDescriptionKey` in `errorUserInfo`, and that text gets through.
    - Docs: `LoadingTheCatalog.md` and `docs/skills-and-agents.md` now give the strict placeholder form, say that `.env.local` is a resource, and tell about the skip for a failed coordinated read.
  timestamp: 2026-10-16T17:37:58.316938+00:00
- actor: claude-code
  id: 01m52wnmve4svxgsxq62rkyxb8
  text: |-
    ### implement — changed
    - evidence: 9 files — Sources/FoundationModelsAgents/Registry/AgentCatalogBuilder.swift, Sources/FoundationModelsAgents/Registry/AgentLayerScan.swift, Sources/FoundationModelsAgents/FoundationModelsAgents.docc/LoadingTheCatalog.md, docs/skills-and-agents.md, Tests/FoundationModelsAgentsTests/AgentFolderPlaceholderTests.swift, Tests/FoundationModelsAgentsTests/Support/AgentFolderFixture.swift, Tests/FoundationModelsAgentsTests/AgentRegistryReloadTests.swift, Tests/FoundationModelsAgentsTests/AgentRegistryMarketplaceTests.swift (plus the task card). RED first: `swift test --filter AgentFolderPlaceholderTests` gave 7 issues in 4 new tests (the false `env` copy hid the user agent; the coordination failure read as "not local yet"). GREEN: 8 tests in 1 suite passed. Then `swift build --build-tests` was clean (the only warning is the known mlx-swift "missing creator for mutated node" line from a dependency). `swift test --filter 'AgentFolder|NoCloudSyncCode|AgentRegistryReload|AgentRegistryMarketplace|LoadingBoundary'` passed 57 tests in 10 suites. Full suite one time: `swift test` passed 557 tests in 78 suites, with 0 failures.
    - next: /review
  timestamp: 2026-10-16T17:38:02.734328+00:00
- actor: claude-code
  id: 01m52wqrpx7gr49280pw3twm14
  text: |-
    ### test — green
    - evidence: `swift test` ran the full suite. Result: 557 tests in 78 suites passed, 0 failed, 0 skipped. Exit code 0.
    - warnings: 0 compiler warnings. One known SwiftPM line remains: "missing creator for mutated node" for the mlx-swift_Cmlx bundle. It is accepted and it is not a compiler warning.
    - changes: no file was changed in this step. No commit was made.
    - next: review.
  timestamp: 2026-10-16T17:39:12.221904+00:00
- actor: claude-code
  id: 01m52wvsnd89fa6se1tejq6jqm
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 29877c4): 0 findings (7 attempted, 0 failed, 0 refuted). The 3 prior findings are fixed: the coordinated read gives a `Result` with `CoordinatedReadFailure` and the real cause (AgentCatalogBuilder.swift); only the name `.AGENT.md.<suffix>` is a placeholder, and a `.env.local` test is added (AgentLayerScan.swift, AgentFolderPlaceholderTests.swift); `AgentFolderFixture.agentText` is the one source, and the private helpers in AgentRegistryMarketplaceTests.swift and AgentRegistryReloadTests.swift call it. All prior items are checked.
    - next: none. The task is in done.
  timestamp: 2026-10-16T17:41:24.269782+00:00
- actor: claude-code
  id: 01m52wwb7rc4c242nb6thpqy5k
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 8 files; the 3 findings fixed and checked
    - test: green — swift test, 557 tests in 78 suites passed, 0 failed, 0 skipped
    - commit: 29877c4
    - review: clean — 0 findings; the task is in done
  timestamp: 2026-10-16T17:41:42.264092+00:00
position_column: done
position_ordinal: e380
title: 'Agent folder source: an optional extra folder of agent folders (the app sets its iCloud Agents/ folder) (D61)'
---
## Why

Decision D61 of the SwissArmyHammer app: the app keeps agents in its iCloud folder `Agents/`. An agent folder is "just a folder":

- `<url>/AGENT.md` at the root of the folder is the **default agent**. Its own folder is `<url>`.
- Each `<url>/<name>/AGENT.md` is one more agent.

The layout has no `agents/` level and no dot folder.

The user said: "this iCloud location is an option to FoundationModelsAgents". Thus:

- The source is an **optional input** that the host gives (one or more folder URLs in the init or the options of the registry).
- It is not a default. A host that does not set it gets the current behavior.
- The package has **no iCloud code**: no container id, no iCloud path, no ubiquity API. The SwissArmyHammer app sets the option to its iCloud `Agents/` URL.

## Problem in the current code

- `AgentCatalogBuilder.build` makes one combined `DotfolderStack` and finds agents with `childDirectories(of: "agents")` and the path `agents/<id>/AGENT.md` (`AgentCatalogBuilder.swift:59`, `:124`). Each layer must have the `agents/` level.
- `AgentBodyRenderer` renders the document at `agents/<id>/AGENT.md` of the winning layer, and the include walks `agents/<id>/_partials/` → `agents/_partials/` → `_partials/`.
- We cannot use the parent folder as the layer root with `Agents` as the folder name: iOS file systems are case-sensitive, and `Agents` is not `agents`.
- The package has **no default agent** now. The `defaults` layer is a layer, not an agent. The host gives the instructions of its root session. Thus the root `AGENT.md` adds a new concept. It does not replace a built-in agent.

## Plan

1. Add an optional input to `AgentRegistry`: `agentFolders: [URL]`, the default is `[]`. Each URL is a folder of agents. With `[]`, the catalog, the layers, and each test do not change.
2. In the builder and the renderer, map the path of each layer: a dotfolder layer uses `agents/<id>/AGENT.md`; an agent-folder source uses `<id>/AGENT.md`, and `AGENT.md` for the default agent. The include walk of an agent-folder agent is `<id>/_partials/` → `_partials/` of the source root. The default agent uses `_partials/` of the source root. Find the smallest change: a per-layer "agents directory" prefix (`"agents"` or `""`), or a request to Extras for a mounted layer.
3. The default agent:
   - Its id is the fixed id `default`. The folder name is not used: `Agents` is not a valid id, and a fixed id lets the precedence work over the layers.
   - `AgentCatalog.defaultAgent` gives the definition with the id `default`, or `nil`. A host starts its root session from it when it is present, and uses its own instructions when it is `nil`. This is how "the root AGENT.md replaces the built-in default" works.
   - Its `folderURL` is `<url>`. Its resources are the files of `<url>` other than `AGENT.md`, `_partials/`, and the agent subfolders.
   - The `name` key of the root file is not checked against the id, because the user gives it a display name. Each other rule applies (an absent description is a warning, and so on).
   - A subfolder `<url>/default/AGENT.md` and a root `AGENT.md` in the same source: the root file wins, and the subfolder gives one warning. A `default` agent in a higher layer (`project/agents/default/AGENT.md`) wins over the root file, with the normal hidden-copy advisory.
   - Two agent-folder URLs with a root `AGENT.md`: the later URL wins, with the hidden-copy advisory.
4. Precedence (agreed with the app session): `marketplace[0] < … < marketplace[n] < defaults < user < agent folders < project`.
5. A file that is not local yet, with generic Foundation code only:
   - A file that the build cannot read, or a placeholder name (`.<name>.icloud` or a different hidden name with the agent folder name in it), does not fail the catalog. It gives one diagnostic "the agent document is not local yet" with its URL. The host starts the download. The next build loads the file.
   - Only the exact name `AGENT.md` is an agent document. A conflict copy (`AGENT 2.md` and the like) is a resource and does not change the agent.
   - Read with `NSFileCoordinator` for the agent-folder source, so that a sync engine can give the current file.
6. Change notifications: with `watch: true`, the `DotfolderWatcher` also watches each agent-folder root. A change from a different device comes as a file change in the folder. The host can also call `reload()` from its own notifications (for example `NSMetadataQuery`). Find out if the watcher sees a placeholder that becomes a full file; if not, document that the host must call `reload()`.
7. A URL that does not exist (for example, iCloud is off) gives an empty source, with no error and no diagnostic.
8. `description`: no change. An absent description is already a warning, and the agent is not in `modelVisible` (`LoadingTheCatalog.md:86`). Thus a model can select only an agent with a description.

## Acceptance

- Tests with a temporary folder in the agent-folder layout: no option gives the current catalog; load; a root `AGENT.md` gives `default` and `defaultAgent`; no root file gives `defaultAgent == nil`; the root and a `default/` subfolder; a project `default` agent wins; precedence; hidden-copy advisory; partials; a placeholder file; a conflict copy; a root that does not exist; a watch event.
- The docs `LoadingTheCatalog.md` and `docs/skills-and-agents.md` tell the option and the default agent.
- A guard test: the package source has no `ubiquity`, `iCloud`, or container id text.

## Review Findings (2026-10-16 12:21)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 15 file(s) reviewed, 14 not reviewed.

> 12 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 12 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/LoadingTheCatalog.md` — no validator matches this file
> - `docs/skills-and-agents.md` — no validator matches this file

- [x] `Sources/FoundationModelsAgents/Registry/AgentCatalogBuilder.swift:253` `swift/error-handling` — The error from the coordinated read is stored in coordinationError and never read. A failed coordination returns nil. readWinner then reports that the document is not local yet (lines 228-232). The real cause is lost, and the user gets a wrong reason for the skip. Return the coordination error to the caller, for example as a Result or a throwing function, so the skip diagnostic states the real failure. If a nil return must stay, pass coordinationError to a log and call assertionFailure when it is set, so the failure is not silent.
- [x] `Sources/FoundationModelsAgents/Registry/AgentLayerScan.swift:204` `design-check/task-description` — `AgentPlaceholderName.folderID(of:)` reads only the file name. Each hidden root file `.<id>.<suffix>` with a valid id becomes a placeholder of the agent folder `<id>`. Thus the usual hidden file `.env.local` at the source root gives a `notLocal` copy of an agent `env`, and a root resource placeholder such as `.notes.icloud` gives a copy of an agent `notes`. The task description (Plan item 5) accepts a hidden name only as a placeholder of an agent document or folder. Also, the agent-folder layer is above `defaults` and `user`, thus this false copy wins over a real `env` agent of a lower layer: `AgentCatalogBuilder.readWinner` gives a `skip`, the real agent goes out of the catalog, and the real copy gets only a hidden-copy advisory. Make the folder-placeholder rule strict so that a hidden file that is not a placeholder does not become an agent, and so that a folder placeholder cannot hide a real copy of a lower layer. Add a test in `AgentFolderPlaceholderTests.swift`: a source root with `.env.local` gives no agent `env` and no diagnostic, and a lower-layer agent with the same id still loads.
- [x] `Tests/FoundationModelsAgentsTests/Support/AgentFolderFixture.swift:60` `reuse/reuse` — The new `agentText(name:body:)` builds the same valid agent file text as private helpers that already exist in other test files. The new fixture adds one more copy instead of being the one shared helper those files call. Over time the copies can drift apart. Make this fixture function the single source of the agent file text. Point the existing private `agentText` helpers in those test files at it, or parameterize the existing copies so the differing parts are arguments to this function. Keep the fixture's fixed `description` and default body as the defaults.