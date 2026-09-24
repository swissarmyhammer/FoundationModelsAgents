---
assignees:
- claude-code
position_column: todo
position_ordinal: '8e80'
title: 'Test support: a scripted step that answers only the newest prompt'
---
## What
`^y4xpk60` needs a scripted model that replies to each delivery post by itself, as a real model does. Now `.finalTextOfLaterPrompts` echoes all earlier prompts, which hides the defect.

- `Tests/FoundationModelsAgentsTests/Support/ScriptedAgentModel.swift` is at the swiftlint `file_length` limit (400 lines). First move one part of it to a new file in `Support/` (for example, the step enum or the executor), with no change in behavior.
- Add a step, for example `.finalTextOfLastPrompt`, that answers with the text of the newest prompt only.

## Acceptance Criteria
- [ ] The new step answers with the newest prompt only, and not with earlier prompts.
- [ ] `ScriptedAgentModel.swift` and the new file are each under the swiftlint `file_length` limit.
- [ ] All existing tests pass with no change.

## Tests
- [ ] A case in `Tests/FoundationModelsAgentsTests/ScriptedProfileTests.swift` for the new step.
- [ ] Run `swift test -Xswiftc -warnings-as-errors` and `swiftlint lint --quiet Sources Tests Examples`. Expected: pass, 0 violations.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.