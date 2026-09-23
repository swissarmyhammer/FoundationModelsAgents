---
assignees:
- claude-code
depends_on:
- 01M376H7W3JTVB6X8M5GBDQNNN
position_column: todo
position_ordinal: '9580'
title: AgentsCLI.makeDriver over the four operations
---
## What
Plan.md §9.4 (the CLI). M6.

- Create `Sources/FoundationModelsAgents/CLI/AgentsCLI.swift`: `public enum AgentsCLI` with `public static func makeDriver(runner: AgentRunner) throws -> OperationCLIDriver`, as `../FoundationModelsSkills/Sources/FoundationModelsSkills/CLI/SkillsCLI.swift` does.
- Commands: `agents agent list [--filter]`, `agents agent start --name … --prompt …`, `agents agent check [--id]`, `agents agent cancel --id`.
- CLI `start` waits for the run and prints the final text (no `ToolContext`, thus no post). `check` and `cancel` are for a host process that stays alive.
- The library writes nothing to standard output; the driver gives the text to its caller.

## Acceptance Criteria
- [ ] `agent list` gives one `- name: description` line for each model-visible agent.
- [ ] `agent start --name code-reviewer --prompt x` gives the scripted final text.
- [ ] An unknown name gives the corrective text and a non-zero exit status.
- [ ] `NoStandardOutWriteTests` stays green.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentsCLITests.swift` drives the driver with arguments and the scripted profile.
- [ ] Run `swift test --filter AgentsCLITests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.