---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3cjj69krash9bvx4tzyftw4
  text: |-
    Research done.
    - AgentFrontmatterReader puts each wrong-type value into `notes`. AgentDefinitionRules.noteFindings makes each note an advisory.
    - ToolResolver gets `definition.tools` and `definition.disallowedTools` from AgentSessionMaker (run) and AgentRunner.runWarnings (catalog). An empty `tools` list gives no tools and no `agents` tool.
    - AgentRun uses `definition.maxTurns` as the pass limit (AgentRunTurns).
    Plan: the frontmatter records each wrong-type key in a new `wrongTypeKeys` list (notes keep only the colon retry). The definition applies the fail-closed values: `tools` -> text items or [], an unreadable deny -> `tools` = [], a bad `maxTurns` -> 1. The rule table gives a warning for each of the three keys; the `disallowedTools` warning is the first finding. Other wrong-type keys stay advisories.
  timestamp: 2026-09-25T15:22:24.435773+00:00
- actor: claude-code
  id: 01m3cmq67ry2tbrcwhwr7xfcy3
  text: |-
    Implementation landed (TDD: I saw the new tests fail for the correct reason, 30 issues, then pass).
    - New `AgentFrontmatter.wrongTypeKeys` (public, sorted). The reader records each wrong-type key there. `notes` now holds only the colon retry note.
    - New `Definition/AgentAccessKey.swift`: the three access keys, in warning order (`disallowedTools`, `tools`, `maxTurns`). Each has a warning text. `failClosedTurnLimit = 1`.
    - `AgentDefinitionRules`: `accessKeyFindings` is the first rule, thus an incorrect `disallowedTools` is the first finding. `wrongTypeFindings` keeps the advisory for the other keys (for example `color: [blue]`).
    - `AgentDefinition`: an incorrect deny gives `tools = []`; an incorrect `tools` gives its text entries or `[]`; an incorrect `maxTurns` (wrong type, or less than 1) gives 1. ToolResolver needs no change, because it reads `definition.tools`.
    - The disallowedTools warning is at the definition layer (registry diagnostics), not in ToolSelection. Reason: the definition sets `tools = []`, so each consumer (catalog warnings and run resolve) gets no tools with no extra flag.
    - plan.md §4.3: three new rows; the advisory row now names the colon retry note and a wrong type on another key.
    - periphery shows only the unused `id` parameters that the `Rule` signature forces (the same as the existing rules).
  timestamp: 2026-09-25T16:00:05.368256+00:00
- actor: claude-code
  id: 01m3cmqgg1rzsn2x2rxqh3chjj
  text: |-
    ### implement — changed
    - evidence: 10 files — Sources/FoundationModelsAgents/Definition/AgentAccessKey.swift (new), AgentDefinition.swift, AgentDefinitionRules.swift, AgentFrontmatter.swift, AgentFrontmatterField.swift, AgentFrontmatterReader.swift; Tests/FoundationModelsAgentsTests/AgentDefinitionRows.swift, AgentDefinitionTests.swift, AgentFrontmatterTests.swift, ToolResolverTests.swift; plan.md. `swift build -Xswiftc -warnings-as-errors` OK; `swift test -Xswiftc -warnings-as-errors`: 331 tests in 45 suites passed; swiftlint 0 violations in 118 files.
    - next: /review
  timestamp: 2026-09-25T16:00:15.873327+00:00
position_column: doing
position_ordinal: '80'
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
- [x] Each case above gives the stated tools or limit, and a warning (not an advisory).
- [x] A correct value of each key behaves as now.

## Tests
- [x] Cases in `Tests/FoundationModelsAgentsTests/AgentFrontmatterTests.swift`, `AgentDefinitionTests.swift`, and `ToolResolverTests.swift`, one for each case above, including the two mixed lists.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.