---
assignees:
- claude-code
depends_on:
- 01M4BXV22HHY1EYE8XEVSV23GW
position_column: todo
position_ordinal: '8680'
title: Each run with a caller gets the messaging tool
---
## What
Change the mount rule so that each run with a caller can send a message to it.

The rule (it applies to a run with `request.context != nil`):

| Case | Tool |
|---|---|
| `Agent`, `Agent(a, b)` or `agents` entry, below `maxDepth` | the full tool (as now) |
| the same entry, at `maxDepth` | the messaging tool (`send caller`, `send agent`) |
| a `tools` key with no such entry | the messaging tool |
| no `tools` key | the messaging tool |
| `disallowedTools` has `agents` or `Agent` | no tool (an explicit deny wins) |

A host-started run (`context == nil`) with no grant gets no tool, as now.

Files:
- `Sources/FoundationModelsAgents/Run/AgentSessionMaker.swift` (`agentsToolFactory` at :130): this is the place that decides the mount, because only it knows `request.context`. Give `.messagingOnly` for the cases above.
- `Sources/FoundationModelsAgents/Tools/ToolResolver.swift` (:64-75): mount the tool that the factory gives when there is no `agentsGrant`, unless `disallowedTools` denies it.
- `Sources/FoundationModelsAgents/Tools/ToolResolver.swift` `diagnostics(... hasAgentsTool:)` and `Sources/FoundationModelsAgents/Run/AgentRunner.swift` :335: at `maxDepth`, the warning says that the `Agent` entry gives only the message ops.

## Acceptance Criteria
- [ ] Each row of the table above has a passing test.
- [ ] The messaging tool description names no agents and no `start agent`.
- [ ] The maxDepth warning text says "only the message ops".

## Tests
- [ ] Update `Tests/FoundationModelsAgentsTests/AgentsToolMountTests.swift`: one test for each row.
- [ ] Update `Tests/FoundationModelsAgentsTests/NestedRunTests+Limits.swift`: at `maxDepth`, expect the messaging tool.
- [ ] Update `Tests/FoundationModelsAgentsTests/ToolResolverTests.swift`: the `disallowedTools` deny, and the maxDepth diagnostic.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.