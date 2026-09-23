---
assignees:
- claude-code
depends_on:
- 01M376K1CKEEBTSGDM55GVBMC3
- 01M376KBXZPH1WESVB084SCRS7
- 01M376J35YTN5ZDS4GF89F9TAG
- 01M376JGKJAWX7DHWQC08C4GCH
position_column: todo
position_ordinal: 9a80
title: 'Documentation: DocC catalog and doc comments'
---
## What
Plan.md §14 M8, the API documentation. All text in ASD-STE100 Simplified Technical English.

- Create `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/FoundationModelsAgents.md` (landing page) and articles for the catalog, a run, the `agents` tool, and the final message.
- Give each public symbol a doc comment.
- Create `Tests/FoundationModelsAgentsTests/DocumentationTests.swift` with one rule: the method of `../FoundationModelsSkills/Tests/FoundationModelsSkillsTests/DocumentationTests.swift`.

## Acceptance Criteria
- [ ] `DocumentationTests` passes.
- [ ] `DocumentationTests` fails when a public symbol loses its doc comment (a test on an in-memory source).
- [ ] The DocC catalog has the landing page and the four articles.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/DocumentationTests.swift`.
- [ ] Run `swift test --filter DocumentationTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.