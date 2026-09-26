---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3ev2a1s9pbfp4vfj22gcxz6
  text: |-
    Research and implementation notes:
    - The change is one line: `ToolVocabulary.everything` now gives `agentsGrant: nil`. `ToolVocabulary.match` still gives the `agents` tool for the explicit entries `Agent`, `Agent(a, b)`, and `agents`. The vocabulary still removes a catalog tool with the name `agents` when the factory is present.
    - `runner.catalog()` warnings did not change: no `tools` key gives no `tools` warnings. `ToolResolver.diagnostics(of:catalog:hasAgentsTool:)` uses the same `ToolSelection`, thus it follows the new rule with no more edit.
    - RED seen first: 2 ToolResolverTests cases and 1 new NestedRunTests.Limits case failed for the expected reason (the run of `helper`, with no `tools` key, got the `agents` tool).
    - The fixture library needs no edit: `lead` has `tools: Agent(code-reviewer, test-writer)`. The agents-demo chat root session gets the `agents` tool directly, thus the demo needs no edit.
    - A fixture that the task did not name also relied on the old rule: `MaxTurnsTests` agents `limited` and `unlimited` call `list agents` to make tool passes. They now have `tools: Agent`.
    - The `disallowedAgentRemovesAgentsTool` test used no `tools` key. With the new rule that test proves nothing, thus it now uses `tools: [Read, Agent]`.
    - Live fixtures: `LiveAgentFile.disallowedTools(_:)` no longer adds `Agent`, and it has no default argument. The answer-only agents (echo-word, storyteller, leaf, flash-by-reference, the live source agents) no longer have a `disallowedTools` line. The agents that must not use the hold tool keep `disallowedTools: hold`.
    - The DocC article `RunningAnAgent.md` still states the old rule. It is in the scope of ^v3stf0j, thus it is not changed here.
    - The live integration tests were not run: they need real models. `cd IntegrationTests && swift build --build-tests` passes. That Tests checkbox stays open.
  timestamp: 2026-09-26T12:29:30.041235+00:00
- actor: claude-code
  id: 01m3ev2fkxg5fbpawtab72p4s4
  text: |-
    ### implement — changed
    - evidence: 10 files — Sources/FoundationModelsAgents/Tools/ToolSelection.swift, Sources/FoundationModelsAgents/Tools/ToolResolver.swift, Tests/FoundationModelsAgentsTests/ToolResolverTests.swift, Tests/FoundationModelsAgentsTests/NestedRunTests+Limits.swift, Tests/FoundationModelsAgentsTests/MaxTurnsTests.swift, IntegrationTests/Tests/AgentsIntegrationTests/{LiveCommandTests,LiveNestedTests,LiveSlotTests}.swift, IntegrationTests/Tests/AgentsIntegrationTests/Support/{LiveAgentFile,LiveSourceTree}.swift. `swift test -Xswiftc -warnings-as-errors`: 359 tests in 49 suites pass. `swift build -Xswiftc -warnings-as-errors`: pass. `cd IntegrationTests && swift build --build-tests`: pass. swiftlint (Sources Tests Package.swift Examples, and IntegrationTests/Tests): 0 violations. Live integration tests not run (they need real models).
    - next: /review. Task stays in doing.
  timestamp: 2026-09-26T12:29:35.741963+00:00
depends_on:
- 01M3A6D0PH2N6Z6BWHGJ8KGEGV
- 01M3A6CQGZZC4VNCQM2Z6EPJ2M
- 01M3A6D97E9AZZKR1K4WWVNSC6
position_column: doing
position_ordinal: '80'
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
- [x] An agent with no `tools` key has every catalog tool except `agents`.
- [x] `tools: Agent` and `tools: agents` give the `agents` tool with all names; `tools: Agent(a, b)` limits it to `a` and `b`.
- [x] `disallowedTools: Agent` still removes it.

## Tests
- [x] Cases in `Tests/FoundationModelsAgentsTests/ToolResolverTests.swift` and `NestedRunTests.swift`.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`, then `cd IntegrationTests && swift test`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.