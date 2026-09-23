---
assignees:
- claude-code
depends_on:
- 01M376GGK2RB6A3XA1PSVRGW9K
- 01M376GQ5AB99BJYWHWW67DVCR
- 01M376J35YTN5ZDS4GF89F9TAG
position_column: todo
position_ordinal: '9380'
title: 'skills: preload into the instructions of a run'
---
## What
Plan.md §5 (`skills:` preload), §8 step 3.

- In `Sources/FoundationModelsAgents/Run/AgentRun.swift` (or a new `AgentRun+Instructions.swift`), at run start, for each name in `definition.skills` call `environment.skills.call(id:)` and append the rendered body to the instructions, after the agent body, in the order of the key.
- An unknown skill, or a skill that is not model-visible, is a warning and is skipped. Add these warnings to `runner.catalog()` diagnostics too (look up the names in `SkillsRegistry` listing).
- The `skills` tool is one entry of the `ToolCatalog` and follows the normal tool rules; the preload does not add the tool.

## Acceptance Criteria
- [ ] An agent with `skills: [review]` has the rendered `review` body in its session instructions, after its own body.
- [ ] Two skills appear in the order of the key.
- [ ] An unknown skill name gives a warning in `runner.catalog()` and the run still starts.
- [ ] A skill with `disable-model-invocation: true` is skipped with a warning.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/SkillsPreloadTests.swift` with a `SkillsRegistry` over `Examples/agent-library/defaults` and the scripted profile.
- [ ] Run `swift test --filter SkillsPreloadTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.