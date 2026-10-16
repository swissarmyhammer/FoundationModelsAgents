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
position_column: doing
position_ordinal: '80'
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