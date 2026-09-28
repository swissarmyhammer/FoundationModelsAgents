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
- actor: claude-code
  id: 01m3mxmt50k0v0brk9j4q8efag
  text: |-
    ### Check against the current code (after ^0mhzx3a, commits ea24368 and 9de4de9)
    - The early count is gone. `converse` in `Examples/agents-demo/DemoModes.swift:350-370` does not read `runner.runs(caller:)` and does not wait for a count of `runSettled` events. It subscribes to `streamSessionEvents()` before the first message (DemoModes.swift:358), one writer task writes the `lines(for:)` of each event (DemoModes.swift:359-361, 378-384), it sends the first prompt and each input line with `send(_:)` (DemoModes.swift:362-365), and it stops only when the input ends (then `cancelRuns(caller:)`, `close()`, and the writer ends; DemoModes.swift:366-368).
    - Thus the time at which the start body adds its run has no effect on the mode. The mode does not count runs, so the count cannot be too small.
    - The "What" item (count from `PendingRunEnvelope` or wait for idle) no longer applies: the mode does not need a count, because the input end is the stop condition. No code change is necessary.
    - The three calls to `runner.runs(caller:)` that stay (DemoModes.swift:169 via `writeRuns`, DemoModes.swift:199, DemoModes.swift:395) run after `cancelRuns(caller:)`, `close()` and the writer end. They only write the final run tree or the fan-out results. They do not control when the mode stops.
    - Acceptance criterion: met. `chatModeWritesTheAnswerToTheMail` (Tests/FoundationModelsAgentsTests/AgentsDemoProfileModeTests.swift:64-101) ends the input only after it read a `settled:` line and the root answer to the mail (lines 84-89).
    - Test item: met. The same test pins the count of `settled:` lines to 1 (AgentsDemoProfileModeTests.swift:94).
    - Verification: `swift build -Xswiftc -warnings-as-errors` exit 0 (the only warnings are SwiftPM manifest cache "disk I/O error" lines and one "missing creator for mutated node" build-system line, no compiler warnings). `swift test -Xswiftc -warnings-as-errors` exit 0: 379 tests in 52 suites passed, 0 XCTest tests.
  timestamp: 2026-09-28T21:10:00.096835+00:00
- actor: claude-code
  id: 01m3mxmw4cdw14tx83tw6j5rm1
  text: |-
    ### implement — no-change
    - evidence: Examples/agents-demo/DemoModes.swift:350-370 (no run count; the mode stops when the input ends); Tests/FoundationModelsAgentsTests/AgentsDemoProfileModeTests.swift:94 (pins 1 `settled:` line); swift build -Xswiftc -warnings-as-errors exit 0; swift test -Xswiftc -warnings-as-errors: 379 tests in 52 suites passed
    - next: /review. Both boxes are checked. The task stays in doing.
  timestamp: 2026-09-28T21:10:02.124577+00:00
position_column: doing
position_ordinal: '80'
title: 'agents-demo --chat: count the start calls from the pending envelopes, not from runner.runs after the first answer'
---
## Why
`AgentsDemoModes.converse` reads `runner.runs(caller: root.id)` just after the answer of the chat prompt, and waits for that count of `runSettled` events. After ^ggpyaem, `start agent` has no settle grace: the body of the call adds the run after the pending envelope, thus the count can be too small (also 0), and the mode can stop before the mail of the runs.

## What
- Count the background runs of the root from the pending envelopes in the tool outputs of the root transcript (`PendingRunEnvelope.makeDecoded(fromRendered:)`), or wait for the root session to be idle, in place of `runner.runs(caller:)`.
- This is host work; coordinate with ^0mhzx3a (hosts on the Router pump).

## Acceptance Criteria
- [x] `agents-demo --chat` with the scripted profile writes each `runSettled` line and the root answer to each mail, also when the start body adds its run after the first answer.

## Tests
- [x] A scripted test of `AgentsDemoModes.chat` that pins the count of `settled:` lines.