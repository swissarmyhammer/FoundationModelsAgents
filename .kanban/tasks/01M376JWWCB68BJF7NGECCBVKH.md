---
assignees:
- claude-code
depends_on:
- 01M376D9AJZB96ZHWEEXGW96QC
- 01M376XK8GJY5DVQ66492JW7TT
position_column: todo
position_ordinal: '9680'
title: 'agents-demo: --watch and --marketplace'
---
## What
Plan.md §13, the demo modes that need no profile. There is no default CLI mode: the CLI needs a resolved profile. Look at `../FoundationModelsSkills/Examples/skills-demo/` and `SkillsDemoTests.swift` for the method.

- `Examples/agents-demo/main.swift`: parse the mode, build the stack over `Examples/agent-library`, and dispatch. With no mode, print the usage.
- `Examples/agents-demo/DemoModes.swift`: put the work of each mode in functions that take their dependencies (registry, an output closure), so tests call them with no process.
  - `--watch`: print one `AgentReloadReport` on each `onReload`.
  - `--marketplace`: use `Examples/agent-library/marketplace` as a `file://` source of a `MarketplaceStore`, and list the agents with provenance.

## Acceptance Criteria
- [ ] `swift run agents-demo` with no mode prints the usage and exits 0.
- [ ] The `--watch` function prints a report after a file in a temporary copy of the library changes.
- [ ] The `--marketplace` function lists `security-reviewer` and `doc-writer` with their marketplace provenance.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentsDemoTests.swift`: run the built binary with no mode, and call the `--watch` and `--marketplace` functions directly.
- [ ] Run `swift test --filter AgentsDemoTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.