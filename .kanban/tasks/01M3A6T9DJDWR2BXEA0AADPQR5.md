---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3d61ebxjnprm2mehye0vv39
  text: 'Research: ScriptedAgentModel.swift has 400 lines. The enum ScriptedTranscriptText (the transcript text readers) is a separate unit at the end of the file. Plan: move it to Support/ScriptedTranscriptText.swift with no change in behavior. Then add the step .finalTextOfLastPrompt and ScriptedTranscriptText.lastPrompt(of:). A shared prompts(of:) helper gives the prompt texts for firstPrompt, laterPrompts and lastPrompt. ScriptedProfileTests has no test for .finalTextOfLaterPrompts now; the new test uses a three-turn flash session.'
  timestamp: 2026-09-25T21:02:47.165827+00:00
- actor: claude-code
  id: 01m3d7525m7pncc7h4ypx02j0j
  text: |-
    Implementation landed.
    - The enum ScriptedTranscriptText moved to Support/ScriptedTranscriptText.swift (78 lines). ScriptedAgentModel.swift now has 344 lines.
    - New step ScriptedAgentStep.finalTextOfLastPrompt. It answers with ScriptedTranscriptText.lastPrompt(of:). A private helper prompts(of:) gives the prompt texts to firstPrompt, laterPrompts and lastPrompt.
    - TDD: the new test first failed to compile. Then the step temporarily used the laterPrompts text, and the test failed on the third turn: it got "the second prompt\n\nthe third prompt". Thus the test finds the echo defect. After the change to lastPrompt, the test passes.
    - Note: the three-turn flash session test shows that a RoutedSession accepts more turns, and each turn goes to the next step of the play.

    ### implement — changed
    - evidence: Tests/FoundationModelsAgentsTests/Support/ScriptedTranscriptText.swift (new), Tests/FoundationModelsAgentsTests/Support/ScriptedAgentModel.swift, Tests/FoundationModelsAgentsTests/ScriptedProfileTests.swift. swift build -Xswiftc -warnings-as-errors: complete. swift test -Xswiftc -warnings-as-errors: 346 tests in 47 suites passed. swiftlint lint --quiet Sources Tests Package.swift Examples: 0 violations. cd IntegrationTests && swift build --build-tests: complete. The only warning is the SwiftPM build-system message "missing creator for mutated node" for the mlx-swift_Cmlx bundle. It was there before this change and is not a compiler warning.
    - next: /review
  timestamp: 2026-09-25T21:22:14.324477+00:00
position_column: doing
position_ordinal: '80'
title: 'Test support: a scripted step that answers only the newest prompt'
---
## What
`^y4xpk60` needs a scripted model that replies to each delivery post by itself, as a real model does. Now `.finalTextOfLaterPrompts` echoes all earlier prompts, which hides the defect.

- `Tests/FoundationModelsAgentsTests/Support/ScriptedAgentModel.swift` is at the swiftlint `file_length` limit (400 lines). First move one part of it to a new file in `Support/` (for example, the step enum or the executor), with no change in behavior.
- Add a step, for example `.finalTextOfLastPrompt`, that answers with the text of the newest prompt only.

## Acceptance Criteria
- [x] The new step answers with the newest prompt only, and not with earlier prompts.
- [x] `ScriptedAgentModel.swift` and the new file are each under the swiftlint `file_length` limit.
- [x] All existing tests pass with no change.

## Tests
- [x] A case in `Tests/FoundationModelsAgentsTests/ScriptedProfileTests.swift` for the new step.
- [x] Run `swift test -Xswiftc -warnings-as-errors` and `swiftlint lint --quiet Sources Tests Examples`. Expected: pass, 0 violations.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.