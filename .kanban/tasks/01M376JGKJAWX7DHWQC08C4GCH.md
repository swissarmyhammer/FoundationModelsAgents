---
assignees:
- claude-code
depends_on:
- 01M376GQ5AB99BJYWHWW67DVCR
- 01M376EDRNA77B46M3GCZN0JQ0
- 01M376XK8GJY5DVQ66492JW7TT
position_column: todo
position_ordinal: '9480'
title: 'SlashCommandProviding: agent commands and skill commands with agent:'
---
## What
Plan.md §9.4 (slash commands). M6.

- First run `swift package update FoundationModelsSkills`, and commit the `Package.resolved` that holds the S1 commit of `FoundationModelsSkills`.
- Create `Sources/FoundationModelsAgents/Commands/AgentRunner+SlashCommands.swift`: `AgentRunner` conforms to `SlashCommandProviding`. `commands(workingDirectory:)` gives:
  - One command for each user-invocable agent: `name`, `description`, `argumentHint: "<task>"`. The `.action` body starts a host-driven run with the text after the name as the prompt, unchanged, waits, and gives the final text.
  - One command for each skill of `environment.skills` whose `SkillListing.agent` names an agent of the catalog: the skill `id`, `description`, `argumentHint`. The body calls `skills.call(id:arguments: [text])`, then starts a run of the named agent with the rendered text as the prompt.
  - A skill `agent:` that names no agent: an `AgentDiagnostic` warning in `runner.catalog()`, and no command.
- `commandUpdates` yields after an agent `onReload` and after a skill `onReload`.
- Fill `AgentReloadReport` slash-command names.

## Acceptance Criteria
- [ ] `Package.resolved` pins a `FoundationModelsSkills` commit that has `SkillListing.agent`.
- [ ] `/code-reviewer check the diff` starts `code-reviewer` with the prompt `check the diff`.
- [ ] A `user-invocable: false` agent has no command.
- [ ] `/review x` renders the `review` skill with `$ARGUMENTS` = `x` and starts `code-reviewer` with the rendered text.
- [ ] `call(id:arguments: [text])` gives the same `$0`, `$1`, and `$name` values as `use skill` with the same text (plan.md §16).
- [ ] An `agent:` that names no agent warns and gives no command.
- [ ] The skill with `agent:` is in the runner commands and not in `SkillsRegistry.commands()`.
- [ ] `commandUpdates` yields after an agent reload and after a skill reload.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/SlashCommandTests.swift` covers each criterion.
- [ ] Run `swift test --filter SlashCommandTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.