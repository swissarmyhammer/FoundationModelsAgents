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
depends_on:
- 01M376F14G9B9QWNG0TTA6VRKT
position_column: doing
position_ordinal: '80'
title: 'AgentRegistry: marketplace layers and provenance'
---
## What
Layer 2, marketplace part (plan.md §4.1, §6.1). No watcher and no reload stream in this task.

- In `Sources/FoundationModelsAgents/Registry/AgentRegistry.swift` add `init(marketplaces: any MarketplaceLayerProviding, stack:variables:watch:)`. The layers are `marketplace[0] < … < marketplace[n] < local layers`, from `provider.marketplaceLayers()`. The build reads `marketplace.layer.root/agents/` of each layer, one level.
- Each marketplace definition keeps its `MarketplaceProvenance` and its marketplace layer (the render task needs the layer for the partial scope).
- Create `Tests/FoundationModelsAgentsTests/Support/FixtureMarketplaceProvider.swift`: a `MarketplaceLayerProviding` over `Examples/agent-library/marketplace` in the §6.1 shape, with `MarketplaceFixtures`.

## Acceptance Criteria
- [ ] A fixture provider of the §6.1 shape gives its agents with provenance.
- [ ] A project agent with the same name wins over a marketplace agent, with an advisory.
- [ ] A marketplace layer with no `agents/` folder gives no agents and no error.
- [ ] A `file://` source with `path:` gives its folder unchanged (plan.md §16), tested with a `MarketplaceStore` over a local folder.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentRegistryMarketplaceTests.swift` covers each criterion.
- [ ] Run `swift test --filter AgentRegistryMarketplaceTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.