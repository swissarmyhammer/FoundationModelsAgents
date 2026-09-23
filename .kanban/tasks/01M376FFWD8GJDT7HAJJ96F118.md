---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37ec1t0s3066d0jnw49skha
  text: |-
    Research:
    - `MarketplaceStore` is an actor. `marketplaceLayers()`, `layerUpdates`, and `diagnostics` are nonisolated. The default policy has no periodic check.
    - A git source over `GitFixtureRepository` gives a snapshot in the §6.1 shape: `agents/<name>.md` of all plugins, `review/SKILL.md`, `_partials/`. The provenance id is the catalog name `agent-library`, and the catalog version is `1.0.0`.
    - A `file://` folder source (no `.git` suffix) with `path:` gives the folder as the layer root. The store copies nothing, and the layer is watchable.
    - `MarketplaceStoreFixture(sources:cacheDirectory:)` with an explicit cache does not remove the cache on deinit. Thus a Sendable struct provider can keep the store and remove the cache itself.
    - `AgentDefinition` already has `layer` and `provenance.marketplace`. Plan: add `marketplaceLayer: MarketplaceLayer?`, and give the builder the marketplace layers.
  timestamp: 2026-09-23T15:32:56.768516+00:00
- actor: claude-code
  id: 01m37er7f72p3j14asc317w6wq
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsAgents/Registry/AgentRegistry.swift, Sources/FoundationModelsAgents/Registry/AgentCatalogBuilder.swift, Sources/FoundationModelsAgents/Definition/AgentDefinition.swift, Tests/FoundationModelsAgentsTests/Support/FixtureMarketplaceProvider.swift, Tests/FoundationModelsAgentsTests/AgentRegistryMarketplaceTests.swift. `swift test -Xswiftc -warnings-as-errors --filter AgentRegistryMarketplaceTests`: 5 tests pass. swiftlint: 0 violations.
    - next: test
  timestamp: 2026-09-23T15:39:35.783102+00:00
- actor: claude-code
  id: 01m37f14mwmpx0adjm5ysvfnq0
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 102 tests in 14 suites passed, 0 failed, 0 skipped (the mlx-swift "missing creator" note is not ours); `swiftlint lint --quiet Sources Tests Examples` — 0 violations.
    - next: commit
  timestamp: 2026-09-23T15:44:27.804075+00:00
- actor: claude-code
  id: 01m37fc1g4m0dxvvfgq8308gca
  text: |-
    ### review — stuck
    - evidence: `review sha HEAD~1..HEAD` — 1 finding (1 confirmed, 0 refuted): `Sources/FoundationModelsAgents/Registry/AgentRegistry.swift:123` `swift/initialization`.
    - blocker: a true conflict. The rule says `init` does no slow work and moves the build to an explicit `load()`. plan.md §4.1 says `catalog()` does no I/O, and plan.md §12 calls `catalog()` directly after `AgentRegistry(marketplaces:stack:variables:watch:)` with no load step, with the `SkillsRegistry` initializers (which build in `init`). The two cannot both hold. A person must correct the rule or the plan.
    - next: a person decides. The task stays in review.
  timestamp: 2026-09-23T15:50:25.028357+00:00
- actor: claude-code
  id: 01m37fc3d7py56612bfzwtqav4
  text: |-
    ### finish iteration 1 — stuck
    - implement: changed — AgentRegistry, AgentCatalogBuilder, AgentDefinition, FixtureMarketplaceProvider, AgentRegistryMarketplaceTests.
    - test: green — 102 tests in 14 suites pass, 0 failed, 0 skipped; swiftlint 0 violations.
    - commit: changed — 2a0e662 feat(registry): read marketplace layers below the local layers and keep their provenance.
    - review: stuck — 1 finding, `swift/initialization` at AgentRegistry.swift:123, in a true conflict with plan.md §4.1 and §12. Recorded as a blocker in the description.
  timestamp: 2026-09-23T15:50:26.983801+00:00
depends_on:
- 01M376F14G9B9QWNG0TTA6VRKT
position_column: review
position_ordinal: '80'
title: 'AgentRegistry: marketplace layers and provenance'
---
## What
Layer 2, marketplace part (plan.md §4.1, §6.1). No watcher and no reload stream in this task.

- In `Sources/FoundationModelsAgents/Registry/AgentRegistry.swift` add `init(marketplaces: any MarketplaceLayerProviding, stack:variables:watch:)`. The layers are `marketplace[0] < … < marketplace[n] < local layers`, from `provider.marketplaceLayers()`. The build reads `marketplace.layer.root/agents/` of each layer, one level.
- Each marketplace definition keeps its `MarketplaceProvenance` and its marketplace layer (the render task needs the layer for the partial scope).
- Create `Tests/FoundationModelsAgentsTests/Support/FixtureMarketplaceProvider.swift`: a `MarketplaceLayerProviding` over `Examples/agent-library/marketplace` in the §6.1 shape, with `MarketplaceFixtures`.

## Acceptance Criteria
- [x] A fixture provider of the §6.1 shape gives its agents with provenance.
- [x] A project agent with the same name wins over a marketplace agent, with an advisory.
- [x] A marketplace layer with no `agents/` folder gives no agents and no error.
- [x] A `file://` source with `path:` gives its folder unchanged (plan.md §16), tested with a `MarketplaceStore` over a local folder.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/AgentRegistryMarketplaceTests.swift` covers each criterion.
- [x] Run `swift test --filter AgentRegistryMarketplaceTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-09-23 10:44)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [ ] `Sources/FoundationModelsAgents/Registry/AgentRegistry.swift:123` `swift/initialization` — Init performs slow work: creating the Generation calls `marketplaceLayers()` on the provider and runs `AgentCatalogBuilder.build()`, which reads and parses files. Callers expect init to return immediately. Defer the catalog build to an explicit `load() throws` method. Store only the provider and local layers in init; build the catalog on demand or when explicitly requested by the caller.

## Blocker
The finding `swift/initialization` at `AgentRegistry.swift:123` is in a true conflict with the documented contract of plan.md:
- plan.md §4.1: "The catalog is cached. `catalog()` does no I/O."
- plan.md §12: the host makes `AgentRegistry(marketplaces:stack:variables:watch:)` and then calls `agents.catalog().listing` with no load call. §12 also says "`AgentRegistry` has the `SkillsRegistry` initializers", and `SkillsRegistry` builds its catalog in its initializer.
- The rule requires that `init` does no slow work, and that the build moves to an explicit `load()`. Then `catalog()` either reads the files (against §4.1) or gives an empty catalog until the host calls `load()` (against §12).
A person must decide: change the rule for registry initializers, or change plan.md §4.1/§12 to add an explicit load step.