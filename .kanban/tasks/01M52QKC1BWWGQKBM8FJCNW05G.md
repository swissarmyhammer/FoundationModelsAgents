---
assignees:
- claude-code
position_column: todo
position_ordinal: '8580'
title: 'A find agents operation: select agents by a semantic search of the descriptions (D61)'
---
## Why

Decision D61 of the SwissArmyHammer app: a `find agents` operation selects agents with a semantic search of the descriptions (embedding), and then a small model picks, as the skills selection does.

## Conflict with a current decision

`docs/skills-and-agents.md:84` says: "`search skill` — Not copied. `list agents` gives the full catalog." D61 replaces this decision. The app session agreed. Update that row in the same change as the operation, so that the doc does not tell about an operation that does not exist yet.

## Plan

1. Examine how FoundationModelsSkills does the selection (`skillsSelectionModel`, the embedding search, the pick by a small model). Use the same parts. Do not copy them.
2. Add `find agents` to the `agents` tool. It searches `modelVisible` agents only, thus an agent with no description is never found.
3. Keep the embedding index current with each catalog from `onReload`.
4. Update `docs/skills-and-agents.md` (the `search skill` row and the D61 reason) and the DocC page of the `agents` tool.

## Acceptance

- Tests with a fixture catalog: a query finds the correct agent; a hidden agent is not found.
- The docs tell the operation.