---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mvyh7pjmddyy1djyer82wk
  text: |-
    ### Note from ^0mhzx3a (the same lines changed)
    ^0mhzx3a removed `AgentsDemoModes.converse` and `deliverSettledRuns` from `Examples/agents-demo/DemoModes.swift`, because that card removes each host wait for settled runs. The mode no longer counts runs: `--chat` and `--fan-out` send the first prompt and each input line with `send(_:)`, one writer task writes a line for each `answered`, `answerFailed`, `runSettled` and `mailDeliveryPaused` event, and the mode ends when its input ends (then `cancelRuns(caller:)`, `close()`, the run tree). Thus the early count of `runner.runs(caller:)` that this card names is gone. The test `chatModeWritesTheAnswerToTheMail` in `Tests/FoundationModelsAgentsTests/AgentsDemoProfileModeTests.swift` ends the input only after it read the settled line and the mail answer, and pins the count of `settled:` lines to 1. ^0mhzx3a did not move or close this card; a person decides if it is still necessary.
  timestamp: 2026-09-28T20:40:21.494943+00:00
position_column: todo
position_ordinal: '9480'
title: 'agents-demo --chat: count the start calls from the pending envelopes, not from runner.runs after the first answer'
---
## Why
`AgentsDemoModes.converse` reads `runner.runs(caller: root.id)` just after the answer of the chat prompt, and waits for that count of `runSettled` events. After ^ggpyaem, `start agent` has no settle grace: the body of the call adds the run after the pending envelope, thus the count can be too small (also 0), and the mode can stop before the mail of the runs.

## What
- Count the background runs of the root from the pending envelopes in the tool outputs of the root transcript (`PendingRunEnvelope.makeDecoded(fromRendered:)`), or wait for the root session to be idle, in place of `runner.runs(caller:)`.
- This is host work; coordinate with ^0mhzx3a (hosts on the Router pump).

## Acceptance Criteria
- [ ] `agents-demo --chat` with the scripted profile writes each `runSettled` line and the root answer to each mail, also when the start body adds its run after the first answer.

## Tests
- [ ] A scripted test of `AgentsDemoModes.chat` that pins the count of `settled:` lines.