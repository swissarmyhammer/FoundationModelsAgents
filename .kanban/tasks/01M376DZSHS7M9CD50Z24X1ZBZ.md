---
assignees:
- claude-code
depends_on:
- 01M376D9AJZB96ZHWEEXGW96QC
position_column: todo
position_ordinal: '8380'
title: Fixture library Examples/agent-library
---
## What
Make the checked-in fixture layers of plan.md §13. The tests and the demo use them.

- `Examples/agent-library/defaults/agents/`: `code-reviewer.md` (`model: flash`, `tools: Read, Grep`), `test-writer.md` (`model: standard`, body holds `$ARGUMENTS`), `lead.md` (`tools: Agent(code-reviewer, test-writer)`).
- `Examples/agent-library/defaults/_partials/house-rules.md`; one defaults agent body includes it.
- `Examples/agent-library/defaults/skills/review/SKILL.md` with `agent: code-reviewer` and `$ARGUMENTS`.
- `Examples/agent-library/user/agents/code-reviewer.md` (a user copy).
- `Examples/agent-library/project/.agents/agents/`: a project copy of `code-reviewer.md` (it replaces the lower copies); one agent with `user-invocable: false`; one with `disable-model-invocation: true`.
- `Examples/agent-library/marketplace/`: `.claude-plugin/marketplace.json`; `plugins/code-tools/_partials/house-rules.md`; `plugins/code-tools/skills/review/SKILL.md`; `plugins/code-tools/agents/security-reviewer.md` (with `skills: [review]`, and its body includes `house-rules.md`); `plugins/docs-tools/agents/doc-writer.md` (with `model: sonnet`).
- `Examples/agent-library/broken/agents/`: `bad-colon-description.md` (an unquoted `:` in `description:`), `missing-description.md`, `bad-name.md` (a `name:` that is not equal to the file name: a warning), `Bad_Name.md` (a file name that breaks the name rule: a skip), `no-frontmatter.md`, `unknown-model.md`, `unknown-disallowed-tool.md`.
- `Tests/FoundationModelsAgentsTests/Support/FixtureLibrary.swift`: URLs of each layer, and a helper that makes a `DotfolderStack` of `defaults < user < project`, as `../FoundationModelsSkills/Tests/FoundationModelsSkillsTests/FixtureLibrary.swift` does.

## Acceptance Criteria
- [ ] All the files above exist and the helper finds each layer.
- [ ] Each `broken/` file holds exactly the one defect that the list above states.
- [ ] `security-reviewer.md` has `skills: [review]` and an include of `house-rules.md`; `doc-writer.md` has `model: sonnet`.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/FixtureLibraryTests.swift`: each expected file exists; the helper stack has three layers in order; `marketplace.json` decodes as JSON.
- [ ] Run `swift test --filter FixtureLibraryTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.