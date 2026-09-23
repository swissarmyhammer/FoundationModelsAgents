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

- Write `docs/skills-and-agents.md`: the §2 table (what transfers from Skills to agents), how one marketplace plugin gives `skills/` and `agents/`, and the partials rule. State that skills and agents are separate things: an agent uses skills through its `skills:` preload and the `skills` tool. To run a skill in its own context, a prompt tells an agent that has the `skills` tool to use the named skill.
- Add a test in `Tests/FoundationModelsAgentsTests/DocsTests.swift` that checks the file exists, holds the §2 table header row, and that each relative link in it resolves to a file in the repository.

## Acceptance Criteria
- [ ] `docs/skills-and-agents.md` exists and holds the §2 table.
- [ ] It states that skills and agents are separate, and how an agent uses a skill.
- [ ] Each relative link in it resolves.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/DocsTests.swift`.
- [ ] Run `swift test --filter DocsTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.