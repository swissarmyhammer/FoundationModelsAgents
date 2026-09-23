---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37ba7qdvc68tpdbx112gm9r
  text: |-
    Research notes:
    - The stack uses `DotfolderStack(name: "agents", ...)`. Thus the project layer root is `project/.agents/`, and the project agents are in `project/.agents/agents/`.
    - The include form is `{% include "house-rules.md" %}`. StenciledDotfolderStack walks from the folder of the document up to the layer root and searches `_partials/` at each level.
    - marketplace.json follows the Extras catalog shape (name, owner, metadata, plugins with `source: ./plugins/<name>` and `strict: false`). The plugins give no `agents` list, thus Extras reads each `.md` in `<plugin>/agents/`.
    - `Bad_Name.md` has `name: Bad_Name`, thus its one defect is the file name.

    ### implement — changed
    - evidence: 23 files — 21 fixtures under Examples/agent-library, Tests/FoundationModelsAgentsTests/Support/FixtureLibrary.swift, Tests/FoundationModelsAgentsTests/FixtureLibraryTests.swift; swiftlint 0 violations
    - next: test
  timestamp: 2026-09-23T14:39:31.565432+00:00
- actor: claude-code
  id: 01m37bby31tp7vcd3fdtakzwhc
  text: |-
    ### test — green
    - evidence: swift test -Xswiftc -warnings-as-errors — 53 tests in 9 suites pass, 0 failed, 0 skipped (the one note is the mlx-swift "missing creator" build-system note, not ours); swiftlint lint --quiet Sources Tests Examples — 0 violations
    - next: commit
  timestamp: 2026-09-23T14:40:27.233546+00:00
- actor: claude-code
  id: 01m37bf3y1zgx76sbj4892abfv
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — 0 findings, 0 confirmed, 0 refuted (2 Swift files reviewed; the 21 fixture files have no matching validator)
    - next: done

    ### finish iteration 1 — clean
    - implement: changed — 21 fixtures, Support/FixtureLibrary.swift, FixtureLibraryTests.swift
    - test: green — 53 tests in 9 suites pass; swiftlint 0 violations
    - commit: changed — 438affb test: add the agent-library fixture layers and FixtureLibrary
    - review: clean — 0 findings
  timestamp: 2026-09-23T14:42:11.521862+00:00
depends_on:
- 01M376D9AJZB96ZHWEEXGW96QC
position_column: done
position_ordinal: '8580'
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
- [x] All the files above exist and the helper finds each layer.
- [x] Each `broken/` file holds exactly the one defect that the list above states.
- [x] `security-reviewer.md` has `skills: [review]` and an include of `house-rules.md`; `doc-writer.md` has `model: sonnet`.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/FixtureLibraryTests.swift`: each expected file exists; the helper stack has three layers in order; `marketplace.json` decodes as JSON.
- [x] Run `swift test --filter FixtureLibraryTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.