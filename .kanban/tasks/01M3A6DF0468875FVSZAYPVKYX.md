---
assignees:
- claude-code
depends_on:
- 01M3A6D0PH2N6Z6BWHGJ8KGEGV
- 01M3A6CQGZZC4VNCQM2Z6EPJ2M
- 01M3A6D97E9AZZKR1K4WWVNSC6
position_column: todo
position_ordinal: '8880'
title: 'Decision A (code): an agent gets the agents tool only when its tools key lists Agent'
---
## Decision (recommended; confirm or change before /finish)
In Claude Code, sub-agents do not start sub-agents by default. Now `ToolVocabulary.everything` (`Sources/FoundationModelsAgents/Tools/ToolSelection.swift`) gives an agent with no `tools` key the full catalog, and that includes the `agents` tool. Most Claude agent files have no `tools` key, so each of them can start any agent, itself too, down to `maxDepth`. The recommendation: the `agents` tool is given only by an explicit entry in `tools`: `Agent`, `Agent(a, b)`, or the plain name `agents` (`ToolVocabulary.match(name:)` also matches that name).

## What
- Leave `agents` out of the "no `tools` key" catalog, in `ToolSelection.swift` and `Tools/ToolResolver.swift` (including `diagnostics(of:catalog:hasAgentsTool:)`).
- `runner.catalog()` tool warnings follow the new rule.
- Update the tests and fixtures that expect an agent with no `tools` key to have the `agents` tool: `ToolResolverTests.swift`, `NestedRunTests.swift` (and `+Limits`), and the live agent files in `IntegrationTests/Tests/AgentsIntegrationTests/` (an answer-only agent no longer needs `disallowedTools: Agent`).
- The documents change in `^v3stf0j`.

## Acceptance Criteria
- [ ] An agent with no `tools` key has every catalog tool except `agents`.
- [ ] `tools: Agent` and `tools: agents` give the `agents` tool with all names; `tools: Agent(a, b)` limits it to `a` and `b`.
- [ ] `disallowedTools: Agent` still removes it.

## Tests
- [ ] Cases in `Tests/FoundationModelsAgentsTests/ToolResolverTests.swift` and `NestedRunTests.swift`.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`, then `cd IntegrationTests && swift test`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.