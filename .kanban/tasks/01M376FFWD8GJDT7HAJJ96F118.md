---
assignees:
- claude-code
depends_on:
- 01M376F14G9B9QWNG0TTA6VRKT
position_column: todo
position_ordinal: '8880'
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