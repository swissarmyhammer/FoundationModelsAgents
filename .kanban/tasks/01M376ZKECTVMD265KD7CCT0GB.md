---
assignees:
- claude-code
depends_on:
- 01M376KBXZPH1WESVB084SCRS7
- 01M376JGKJAWX7DHWQC08C4GCH
position_column: todo
position_ordinal: a180
title: docs/skills-and-agents.md
---
## What
Plan.md §14 M8: a document on skills and agents. ASD-STE100 Simplified Technical English.

- Write `docs/skills-and-agents.md`: the §2 table (what transfers from Skills to agents), how one marketplace plugin gives `skills/` and `agents/`, the partials rule, and the `agent:` key of a skill.
- Add a test in `Tests/FoundationModelsAgentsTests/DocsTests.swift` that checks the file exists, holds the §2 table header row, and that each relative link in it resolves to a file in the repository.

## Acceptance Criteria
- [ ] `docs/skills-and-agents.md` exists and holds the §2 table.
- [ ] Each relative link in it resolves.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/DocsTests.swift`.
- [ ] Run `swift test --filter DocsTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.