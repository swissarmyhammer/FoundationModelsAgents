---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mtp0mmaw14s4e4tj0qa45t
  text: |-
    ### Research (2026-09-28)
    What ^ggpyaem already did for the hosts:
    - README usage block and `ReadmeExampleSource.swift` already use `respond(to:)`, then read the first `answered` event with an empty `messageIds` (the mail answer). `ReadmeExampleTests` already checks that answer. No change is necessary there.
    - `Commands/AgentRunner+SlashCommands.swift` and `CLI/AgentsCLIOperations.swift` call `runner.start(_:prompt:)` and `result()` only. They call no Router driver method. The session pump of the run delivers the mail of its children.

    What remains:
    - `Examples/agents-demo/DemoModes.swift`: `--chat` sends the first prompt with `streamEvents(to:)` and then waits in `deliverSettledRuns` for a count of `runSettled` events that it reads from `runner.runs(caller:)` after the first answer. That is the wait for settled runs that the card removes. The same lines are the subject of ^thxe76k. `--fan-out` is two host-driven `start` + `result()` runs; it does not show the mail flow.

    Router facts (960dab2):
    - `send(_:)`, `respond(to:)` and mail give the reply whole in `answered`; only a streamed submission sends `textDelta`.
    - `close()` sweeps each background run (the `agents` tool canceler) and finishes each `streamSessionEvents()` subscription. Thus a writer task over the session events ends at `close()`.
    - `mailDeliveryPaused(MailDeliveryPause)` has a public init, thus a unit test can give it to the line function.

    Plan:
    - `--chat` and `--fan-out` share one conversation: send the first prompt with `send(_:)`, then send each line of the input; one writer task writes a line for each `answered`, `answerFailed`, `runSettled` and `mailDeliveryPaused` event (the pause line tells the user to send a message). At the end of the input, `cancelRuns(caller:)`, `close()`, wait for the writer, then write the run report. No count and no wait for settled runs.
    - `--fan-out`: the root session starts code-reviewer (flash) and test-writer (standard) with the agents tool; each final message comes as mail. At the end, one fan-out line for each run.
    - Tests: the chat and fan-out tests give an input stream, and end the input only after they read the mail answer line. New unit tests for the event lines. New CLI and slash-command tests: `lead` (which starts two children) gives its final text with no driver call.
  timestamp: 2026-09-28T20:18:13.780011+00:00
- actor: claude-code
  id: 01m3mvyr3aqhcmhxfeq1fvcd1p
  text: |-
    ### Implementation notes
    - The same lines as ^thxe76k changed: `converse` and `deliverSettledRuns` (the run count after the first answer) are gone. A note is on ^thxe76k. That card was not moved.
    - `--fan-out` is now a root session with the agents tool that starts code-reviewer (flash) and test-writer (standard) at once, as the card asks ("the same flow for several children"). The run lines (`<agent> on <model>: <text>`) come after the end of the input. plan.md §13 line of `--fan-out` changed from "host-driven runs on the two slots" to match; ^7f7z6qa owns the other plan text.
    - The modes end when the input ends (standard input in the binary; Control-D). This is the only end, because the card forbids a wait for settled runs.
    - `textDelta`: `send(_:)` and mail give the reply whole in `answered` (Router `SessionEvent` doc), and send no `textDelta`. Thus the answer line comes from `answered`, and `lines(for:)` gives no line for `textDelta`; a unit test pins that.
    - TDD: the demo tests and the event-line tests failed first (compile: no `AgentsDemoInput`, `lines(for:)`, `fanOutInstructions`, `failedPrefix`, `pausedPrefix`, `sendMessageHint`, `cancelledText`). The new CLI test (`startOfAParentGivesItsAnswerToTheMail`) and slash test (`commandOfAParentGivesItsAnswerToTheMail`) passed at the first run: they are the check that the card asks for ("check that they need no driver call"), and the production code of those two hosts needed no change. Only their doc comments changed.
    - README and `ReadmeExampleSource.swift` already had the mail flow from ^ggpyaem; `ReadmeExampleTests` passes with no change.
    - The cancel test waits for the gate arrival of the late run before it ends the input, thus the run is registered before `cancelRuns(caller:)` (see ^x428x7j for the race of a run that is not added yet).
  timestamp: 2026-09-28T20:40:28.522735+00:00
- actor: claude-code
  id: 01m3mvyy57cejnjvqnqfbafnrs
  text: |-
    ### implement — changed
    step: implement
    outcome: changed
    evidence: 10 files. Examples/agents-demo/DemoModes.swift, Examples/agents-demo/AgentsDemoMain.swift, Examples/agents-demo/AgentsDemoMode.swift, Sources/FoundationModelsAgents/Commands/AgentRunner+SlashCommands.swift (doc), Sources/FoundationModelsAgents/CLI/AgentsCLIOperations.swift (doc), Sources/FoundationModelsAgents/CLI/AgentsCLI.swift (doc), plan.md (§13 --fan-out line), Tests/FoundationModelsAgentsTests/AgentsDemoProfileModeTests.swift (new; the profile suite moved out of AgentsDemoTests.swift, plus an event-line suite), Tests/FoundationModelsAgentsTests/AgentsDemoTests.swift, Tests/FoundationModelsAgentsTests/AgentsCLITests.swift, Tests/FoundationModelsAgentsTests/SlashCommandTests.swift. swift build -Xswiftc -warnings-as-errors: pass; agents-demo builds. swift test -Xswiftc -warnings-as-errors: 379 tests in 52 suites passed. The demo, CLI and slash suites: 34 tests in 5 suites passed 3 more runs. swiftlint lint Sources Tests Package.swift Examples: 0 violations in 130 files. cd IntegrationTests && swift test: 12 tests in 6 suites passed (364.2 s). SwiftPM prints "failed loading cached manifest ... disk I/O error" and "missing creator for mutated node" warnings; they are not compiler warnings. Not committed, not pushed.
    - next: /review ^0mhzx3a. A person decides if ^thxe76k is still necessary (note on that card).
    task: ^0mhzx3a
  timestamp: 2026-09-28T20:40:34.727716+00:00
depends_on:
- 01M3A6EGTPK2A08N066GGPYAEM
position_column: doing
position_ordinal: '80'
title: 'Hosts on the Router pump: agents-demo, slash commands, the CLI and the README example'
---
## What
After ^ggpyaem, the Router pump delivers messages and settled runs. A host sends with `send(_:)` or `respond(to:)` and does not drive a loop.
- `Examples/agents-demo/DemoModes.swift`: remove the driver loop (`chat`, `converse`, `deliverSettledRuns`). `--chat` sends each user line with `send(_:)` and prints the answers from `streamSessionEvents()` (`answered`, `textDelta`), including the answers that mail starts. `--fan-out` shows the same flow for several children.
- `Commands/AgentRunner+SlashCommands.swift` and `CLI/AgentsCLIOperations.swift`: keep `start` + `result()`, and check that they need no driver call. Correct the doc comments.
- The README example (`README.md` and `Tests/FoundationModelsAgentsTests/ReadmeExampleSource.swift`): a root session with the `agents` tool uses `respond(to:)` and then gets the child's result as mail with no host loop.
- `mailDeliveryPaused` at a host: the demo prints it and tells the user to send a message.

## Acceptance Criteria
- [x] No host code calls a driver method or waits in a loop for settled runs.
- [x] The demo `--chat` shows the answer that the child's mail starts, with no user input.
- [x] `ReadmeExampleTests` runs the example with the scripted model and sees the parent's answer to the child's mail.

## Tests
- [x] Update `AgentsDemoTests.swift`, `ReadmeExampleTests.swift`, `ReadmeExampleSource.swift`, `AgentsCLITests.swift`, and the slash command tests.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.
- [x] Run `cd IntegrationTests && swift test`. Expected: pass. Report the real results.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.