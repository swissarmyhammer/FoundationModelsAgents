---
position_column: done
position_ordinal: ff9e80
title: 'AgentEnvironment.make: give a marketplace registry to the skills tool'
---
FoundationModelsACPAgent mounts the marketplace list of the agent (Extras `MarketplaceRegistry`, D190). The skills tool gets the list through `SkillsToolContext(..., marketplaces:)`, and its `SkillsGraph` gets it too.

`AgentEnvironment.make` makes the skills tool through `SkillsTool.make(registry:...)`, with no marketplaces. Thus a host cannot give the list.

- Add `skillsMarketplaces: MarketplaceRegistry? = nil` to `AgentEnvironment.make` and `makeSkillsTool`, and give it to `SkillsTool.make(..., marketplaces:)`.
- This needs FoundationModelsSkills first: the `marketplaces:` parameter on both `SkillsTool.make(registry:...)` overloads (requested from the Skills session).
- Test: a registry given to `make` gives the skills tool the marketplace operations (`list marketplace`).
- Send the commit to the FoundationModelsACPAgent session.