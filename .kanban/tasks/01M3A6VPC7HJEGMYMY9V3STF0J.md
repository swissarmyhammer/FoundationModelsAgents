---
assignees:
- claude-code
depends_on:
- 01M3A6DF0468875FVSZAYPVKYX
- 01M3A6C3W4FTNNC249NNVFWH3M
position_column: todo
position_ordinal: 8f80
title: 'Decision A (docs): the plan and the documents state the explicit Agent rule'
---
## What
After `^aypvkyx`, the documents must state the new rule: an agent gets the `agents` tool only through an explicit `Agent`, `Agent(a, b)`, or `agents` entry in `tools`. With no `tools` key it gets every other catalog tool.

- plan.md §5: rewrite "The `agents` tool is in the catalog under the name `agents`, so the same rules apply", and the "No `tools` key gives the full catalog" rule.
- `README.md` (the frontmatter key table), `docs/skills-and-agents.md` if it mentions it, and the DocC articles `RunningAnAgent.md` and `DelegatingWithTheAgentsTool.md`.

## Acceptance Criteria
- [ ] plan.md §5, the README, and the DocC articles state the same rule, with no sentence that says a missing `tools` key gives the `agents` tool.

## Tests
- [ ] Add the rule as a required claim in `Tests/FoundationModelsAgentsTests/DocumentationTests.swift` (the method it uses for design claims).
- [ ] Run `swift test --filter "DocumentationTests|ReadmeExampleTests|DocsTests"`, then the full suite. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.