---
assignees:
- claude-code
depends_on:
- 01M376D9AJZB96ZHWEEXGW96QC
position_column: todo
position_ordinal: 9d80
title: 'ToolSpec: parse tools and disallowedTools entries'
---
## What
Plan.md §5. Parse one entry of `tools` or `disallowedTools` into a typed value.

- Create `Sources/FoundationModelsAgents/Definition/ToolSpec.swift`: `enum ToolSpec: Equatable { case name(String), mcpPrefix(String), mcpAll, agent(allowed: [String]?) }` and `static func parse(_ entry: String) -> ToolSpec`.
  - `Agent` alone gives `agent(allowed: nil)`; `Agent(a, b)` gives `agent(allowed: ["a", "b"])`, in order, with spaces trimmed.
  - `mcp__srv` and `mcp__srv__*` give `mcpPrefix("mcp__srv")`; `mcp__*` gives `mcpAll`.
  - Other text gives `name`.

## Acceptance Criteria
- [ ] Each form above parses to the stated value.
- [ ] `Agent()` and `Agent( a ,b )` give defined results (empty list; `["a", "b"]`).

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/ToolSpecTests.swift`.
- [ ] Run `swift test --filter ToolSpecTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.