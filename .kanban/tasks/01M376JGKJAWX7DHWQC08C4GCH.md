---
assignees:
- claude-code
depends_on:
- 01M376GQ5AB99BJYWHWW67DVCR
- 01M376XK8GJY5DVQ66492JW7TT
position_column: todo
position_ordinal: '9480'
title: 'SlashCommandProviding: one command for each user-invocable agent'
---
## What
Plan.md §9.4 (slash commands). Skills and agents are separate things; this package gives commands for agents only.

- Create `Sources/FoundationModelsAgents/Commands/AgentRunner+SlashCommands.swift`: `AgentRunner` conforms to `SlashCommandProviding`. `commands(workingDirectory:)` gives one command for each user-invocable agent: `name`, `description`, `argumentHint: "<task>"`. The `.action` body starts a host-driven run with the text after the name as the prompt, unchanged, waits, and gives the final text.
- `commandUpdates` yields after each agent `onReload`.
- Fill `AgentReloadReport` slash-command names.
- In `Examples/agent-library/defaults/skills/review/SKILL.md`, remove the `agent: code-reviewer` key, and update `FixtureLibraryTests` to match.

## Acceptance Criteria
- [ ] `/code-reviewer check the diff` starts `code-reviewer` with the prompt `check the diff`, and the command gives its final text.
- [ ] A `user-invocable: false` agent has no command.
- [ ] `commandUpdates` yields after an agent reload, with the new command list.
- [ ] `AgentReloadReport` lists the slash-command names.
- [ ] No fixture skill has an `agent:` key.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/SlashCommandTests.swift` covers each criterion.
- [ ] Run `swift test --filter "SlashCommandTests|FixtureLibraryTests"`, then the full suite. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.