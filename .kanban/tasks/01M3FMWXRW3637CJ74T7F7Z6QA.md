---
assignees:
- claude-code
depends_on:
- 01M3A6EGTPK2A08N066GGPYAEM
position_column: todo
position_ordinal: '9180'
title: 'Documents for background runs: plan §8 and §9, the README, TheFinalMessage and the tool text'
---
## What
State the run model of ^ggpyaem in every document. Plans state intent, not history.
- `plan.md` §8 (a run and its session), §9 (the `agents` tool, the final message, delivery), and every place that names `dispatchNextPrompt()`, delivery turns, or the final-answer prompt (the research found lines near 355, 362-363, 483, 491, 662, 826). New text: `start agent` is a background run; the final message is the run detail and comes to the parent as mail; the Router pump delivers it; a run ends when its session is idle; `maxTurns` counts passes from the live events.
- `README.md` (near lines 135 and 159), `FoundationModelsAgents.docc/TheFinalMessage.md` (near 45, 52, 57), `DelegatingWithTheAgentsTool.md`, `RunningAnAgent.md`.
- `Tool/AgentsToolText.swift`: the text for `start agent` agrees with the Router pending envelope. The model must end its answer to receive the mail.
- `Tests/FoundationModelsAgentsTests/DocumentationTests.swift`: replace the claim that names `dispatchNextPrompt()` (near line 132) with claims for the new model.
- Doc comments in `Run/AgentRunProgress.swift`, `Run/AgentRun*.swift` that name the removed driver or delivery turns.

## Acceptance Criteria
- [ ] No document or doc comment names `dispatchNextPrompt`, `enqueue(prompt:)`, `cancelCurrentTurn`, delivery turns, or the final-answer prompt.
- [ ] `DocumentationTests` holds claims for: a background run, mail delivery, and the idle rule.

## Tests
- [ ] Update `DocumentationTests.swift` first and see the new claims fail.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.