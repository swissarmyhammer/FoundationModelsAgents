---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37deqf7cyt1smmc9xega9et
  text: |-
    Research done.
    - `DotfolderStack.enumerate("agents", suffix: ".md")` gives the top level only, keyed by name with the suffix removed. It gives the winning `Located<String>`.
    - `DotfolderStack.locate(_:)` gives the URLs of all copies, but not the layer index. The registry finds the layers that hold a path with `DotfolderStack(layers: [layer]).exists(path)` for each layer. The last index is the winner; each lower index is a hidden copy.
    - `FrontmatterDocumentStack.onDiagnostic` fires only when a frontmatter block does not decode. No broken fixture fires it (the colon retry decodes `bad-colon-description`; `no-frontmatter` has no block).
    - `SkillsRegistry` holds its catalog in an `NSLock` box. This task uses `Mutex` from `Synchronization` (macOS 27 floor).
    - `FixtureLibraryTests.localAgentIds` holds the five local ids. The registry tests need the same set, thus it moves to `FixtureLibrary.localAgentIDs`.
  timestamp: 2026-09-23T15:16:55.911798+00:00
- actor: claude-code
  id: 01m37dtwzkk56n4ystprcnv2tq
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsAgents/Registry/AgentCatalog.swift, Sources/FoundationModelsAgents/Registry/AgentCatalogBuilder.swift, Sources/FoundationModelsAgents/Registry/AgentRegistry.swift, Tests/FoundationModelsAgentsTests/AgentRegistryTests.swift, Tests/FoundationModelsAgentsTests/Support/TemporaryLayer.swift, Tests/FoundationModelsAgentsTests/Support/FixtureLibrary.swift (+ FixtureLibraryTests uses FixtureLibrary.localAgentIDs). `swift test --filter "AgentRegistryTests|LoadingBoundaryTests|FixtureLibraryTests"`: 31 tests pass. swiftlint: 0 violations.
    - notes: a frontmatter that does not decode gives an advisory (the Extras hook message), then the skip of AgentDefinition. A `// periphery:ignore:parameters watch` marker stands above the doc comment of `init(layers:variables:watch:)`; below the doc comment it breaks swiftlint `orphaned_doc_comment`.
    - next: test
  timestamp: 2026-09-23T15:23:34.771896+00:00
- actor: claude-code
  id: 01m37dy6c4pcm76853qxp1cn0k
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 97 tests in 13 suites pass, 0 failed, 0 skipped (the mlx-swift "missing creator" build-system note is not of this package); `swiftlint lint --quiet Sources Tests Examples` — 0 violations.
    - next: commit
  timestamp: 2026-09-23T15:25:22.692455+00:00
- actor: claude-code
  id: 01m37dycxwgkh9xzje2n1ahkk2
  text: |-
    ### commit — changed
    - evidence: a9090cd feat(registry): build AgentCatalog from local layers with one-level read and cached catalog()
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T15:25:29.404760+00:00
- actor: claude-code
  id: 01m37e6afszmkbq9jbjfe5wknc
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 0 confirmed, 0 refuted; 7 files reviewed, 0 failed.
    - next: done

    ### finish iteration 1 — clean
    - implement: changed (AgentCatalog, AgentCatalogBuilder, AgentRegistry, AgentRegistryTests, TemporaryLayer, FixtureLibrary.localAgentIDs)
    - test: green (`swift test -Xswiftc -warnings-as-errors` — 97 tests in 13 suites pass; swiftlint 0 violations)
    - commit: changed (a9090cd)
    - review: clean (0 findings)
  timestamp: 2026-09-23T15:29:49.049643+00:00
depends_on:
- 01M376ER95A0C8N4KHFP9QS1JY
- 01M376DS6RBPHB0AEP6604D8Z7
position_column: done
position_ordinal: '8980'
title: 'AgentRegistry: local layers, one-level read, AgentCatalog'
---
## What
Layer 2, local part (plan.md §4.1, §4.3 step 1, §12). No marketplace and no watcher in this task.

- `Sources/FoundationModelsAgents/Registry/AgentCatalog.swift`: `public struct AgentCatalog: Sendable` with `definitions`, `listing: [AgentListing]`, `diagnostics: [AgentDiagnostic]`, `definition(named:) -> AgentDefinition?`, `modelVisible`.
- `Sources/FoundationModelsAgents/Registry/AgentRegistry.swift`: `public final class AgentRegistry: Sendable` with `init(stack:variables:watch:)` and `init(layers:variables:watch:)` (the `SkillsRegistry` initializers). `catalog()` does no I/O and gives the cached catalog. `reload()` rebuilds and swaps it atomically (a `Mutex`).
- Build: a `FrontmatterDocumentStack(base: plain, decode: AgentFrontmatter.decode, onDiagnostic:)`; `plain.enumerate(MarketplaceLayer.agentsDirectoryName, suffix: ".md")` (one level); `documents.item(at: "agents/<id>.md")`; then `AgentDefinition.init`.
- The highest layer wins a path. Each lower copy gives an advisory on the winner's diagnostics.
- Each definition keeps its URL, its layer, and its layer index. The layer is kept for the render (§4.3 step 3).
- Keep `variables` on the registry for the render task.
- All file access goes through Extras; the guard tests must stay green.

## Acceptance Criteria
- [x] The fixture stack gives the expected ids; the file name is the id.
- [x] The user `code-reviewer.md` wins over the defaults copy, with one advisory.
- [x] A `.md` file in a subfolder of `agents/` is not read.
- [x] Each `broken/` file gives its diagnostic, and the good files next to it load.
- [x] `catalog()` gives the same value with no I/O after the build (a second call after the files are deleted gives the same catalog until `reload()`).

## Tests
- [x] `Tests/FoundationModelsAgentsTests/AgentRegistryTests.swift` covers each criterion.
- [x] Run `swift test --filter AgentRegistryTests`, then the guard tests. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.