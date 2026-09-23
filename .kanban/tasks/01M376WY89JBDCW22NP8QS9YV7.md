---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37cccs605kppr21ygfbjjrb
  text: |-
    Research: `AgentFrontmatterReader.entries(inCommaSeparated:)` splits at commas out of parentheses, trims, and removes empty entries. `ToolSpec.parse` uses it again for the names in `Agent(...)`, thus `Agent()` gives `[]` and `Agent( a ,b )` gives `["a", "b"]`.

    Decisions: `ToolSpec` is internal (no public use yet). The parse trims the entry. `mcp__srv__tool` (one MCP tool) gives `name`. `mcp__`, `mcp__s*`, `Agentx`, and `Agent(a` give `name`.

    TDD: the red build failed with "cannot find type 'ToolSpec'". Then `swift test --filter ToolSpecTests`: 2 tests (17 table cases) pass. swiftlint: 0 violations.

    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsAgents/Definition/ToolSpec.swift, Tests/FoundationModelsAgentsTests/ToolSpecTests.swift
    - next: test
  timestamp: 2026-09-23T14:58:10.854084+00:00
- actor: claude-code
  id: 01m37cdvcvkqrhrwrck2zzw55h
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 68 tests in 11 suites passed, 0 failed, 0 skipped, 0 warnings; `swiftlint lint --quiet Sources Tests Examples` — 0 violations
    - next: commit
  timestamp: 2026-09-23T14:58:58.587259+00:00
- actor: claude-code
  id: 01m37ce0e3z1mmh6ke2jvr30p5
  text: |-
    ### commit — changed
    - evidence: a879428 feat(definition): parse tools and disallowedTools entries into ToolSpec
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T14:59:03.747199+00:00
- actor: claude-code
  id: 01m37cgxs0g3rss8pkf36rwx97
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 0 confirmed, 0 refuted (7 attempted, 0 failed); 2 .kanban files excluded by .reviewignore
    - next: done

    ### finish iteration 1 — clean
    - implement: changed — ToolSpec.swift, ToolSpecTests.swift
    - test: green — 68 tests in 11 suites, 0 failed, 0 skipped, 0 warnings; swiftlint 0 violations
    - commit: changed — a879428
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-23T15:00:39.328050+00:00
depends_on:
- 01M376D9AJZB96ZHWEEXGW96QC
position_column: done
position_ordinal: '8780'
title: 'ToolSpec: parse tools and disallowedTools entries'
---
## What
Plan.md §5. Parse one entry of `tools` or `disallowedTools` into a typed value.

- Create `Sources/FoundationModelsAgents/Definition/ToolSpec.swift`: `enum ToolSpec: Equatable { case name(String), mcpPrefix(String), mcpAll, agent(allowed: [String]?) }` and `static func parse(_ entry: String) -> ToolSpec`.
  - `Agent` alone gives `agent(allowed: nil)`; `Agent(a, b)` gives `agent(allowed: ["a", "b"])`, in order, with spaces trimmed.
  - `mcp__srv` and `mcp__srv__*` give `mcpPrefix("mcp__srv")`; `mcp__*` gives `mcpAll`.
  - Other text gives `name`.

## Acceptance Criteria
- [x] Each form above parses to the stated value.
- [x] `Agent()` and `Agent( a ,b )` give defined results (empty list; `["a", "b"]`).

## Tests
- [x] `Tests/FoundationModelsAgentsTests/ToolSpecTests.swift`.
- [x] Run `swift test --filter ToolSpecTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.