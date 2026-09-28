---
assignees:
- claude-code
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