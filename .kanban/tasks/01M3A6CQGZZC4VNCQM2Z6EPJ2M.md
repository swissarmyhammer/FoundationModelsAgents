---
assignees:
- claude-code
position_column: todo
position_ordinal: '8480'
title: A frontmatter key of the wrong type fails closed, not open
---
## What
In `Sources/FoundationModelsAgents/Definition/AgentFrontmatterReader.swift` (`list`, `wholeNumber`, `listEntries`), a value of the wrong type gives `nil` or drops items, with only an advisory note (`AgentDefinitionRules` treats decode notes as advisories). The results give more access than the author wanted:
- `tools: 3` gives `nil`, which is the full catalog;
- `disallowedTools: {Bash: true}` denies nothing;
- `disallowedTools: [Bash, 3]` keeps `Bash` and drops `3` with only an advisory;
- `maxTurns: "5"` gives no limit.

Change it:
- `tools` of the wrong type: the agent gets no tools (`[]`) and a warning. A `tools` list with an item that is not text: the text items are kept, and a warning.
- `disallowedTools` of the wrong type, or a list with an item that is not text: a warning that sorts first, as for an unknown deny entry (plan §5). The agent gets no tools, because the deny cannot be read in full.
- `maxTurns` of the wrong type, or not greater than 0: a warning. The agent runs with a limit of 1 pass, so an error stops a loop and does not remove the limit.
- Update the rule table in plan.md §4.3.

## Acceptance Criteria
- [ ] Each case above gives the stated tools or limit, and a warning (not an advisory).
- [ ] A correct value of each key behaves as now.

## Tests
- [ ] Cases in `Tests/FoundationModelsAgentsTests/AgentFrontmatterTests.swift`, `AgentDefinitionTests.swift`, and `ToolResolverTests.swift`, one for each case above, including the two mixed lists.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.