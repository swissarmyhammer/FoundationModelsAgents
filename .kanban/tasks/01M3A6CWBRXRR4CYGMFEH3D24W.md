---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3cy7bwv5czx37ve9knq57gy
  text: 'Research: `AgentRun.result()` calls `finalState()`, which awaits `turn.value` of a detached task. A cancel of the waiting task does not reach the detached turn. `AgentRun.cancel()` cancels the turn task, and `drive` maps the cancel to `.cancelled`. `finalText(ofAgent:)` in `AgentRunner+SlashCommands.swift` has its own `withTaskCancellationHandler`. `StartAgentCommand.execute(in:)` in `CLI/AgentsCLIOperations.swift` returns `try await run.result()` and maps an error to `AgentsCLIFailure(run.report)`. The existing test `SlashCommandTests.cancelOfTheStreamCancelsTheRun` covers the slash command. Plan: new tests in `AgentRunTests` (a task that waits in `result()` is cancelled) and `AgentsCLITests` (a cancel of the task of `driver.run` cancels the run), then move the handler into `result()`.'
  timestamp: 2026-09-25T18:46:12.635463+00:00
- actor: claude-code
  id: 01m3d1t56sjwft1dtjadkssb0h
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsAgents/Run/AgentRun.swift (`result()` wraps `finalState()` in `withTaskCancellationHandler`, onCancel calls `cancel()`; doc comment states the behavior), Sources/FoundationModelsAgents/Commands/AgentRunner+SlashCommands.swift (duplicate handler removed; `finalText` is `try await start(name, prompt: prompt).result()`), Sources/FoundationModelsAgents/CLI/AgentsCLIOperations.swift (doc comment only), Tests/FoundationModelsAgentsTests/AgentRunTests.swift (`cancelOfWaitingTaskCancelsRun`), Tests/FoundationModelsAgentsTests/AgentsCLITests.swift (`cancelOfStartCancelsRun`).
    - RED: both new tests exceeded their 60 s time limit before the change (the run went on after the cancel of the waiting task).
    - GREEN: `swift test -Xswiftc -warnings-as-errors` 340 tests in 46 suites pass; `swift build -Xswiftc -warnings-as-errors` pass; `swiftlint lint Sources Tests Package.swift Examples` 0 violations; `cd IntegrationTests && swift build --build-tests` pass. The existing `SlashCommandTests.cancelOfTheStreamCancelsTheRun` stays green.
    - Note: `swift test` output goes to a pipe only when the process exits. To see a hang, run `swiftpm-testing-helper` direct with `DYLD_FRAMEWORK_PATH` set to the platform Developer frameworks.
    - next: /review
  timestamp: 2026-09-25T19:48:54.105586+00:00
depends_on:
- 01M3A6BZSVQR5RJ7TNBJ0Z9Y9Q
position_column: doing
position_ordinal: '80'
title: result() cancels the run when the waiting task is cancelled
---
## What
`AgentRun.result()` (`Sources/FoundationModelsAgents/Run/AgentRun.swift`) waits on `finalState()`, which awaits `turn.value` and ignores the cancel of the task that waits. Example: in the README fan-out, `async let a = runner.start(...).result()`. A throw in the sibling cancels `a`, but the host still waits for the whole run of `a`, and the run goes on.

- Wrap the wait of `result()` in `withTaskCancellationHandler { … } onCancel: { run.cancel() }`. Then `result()` throws `CancellationError` when the run ends as cancelled.
- The CLI start (`CLI/AgentsCLIOperations.swift`) already returns `try await run.result()`, so it gets the fix through `result()`.
- `Commands/AgentRunner+SlashCommands.swift` `finalText(ofAgent:)` has its own `withTaskCancellationHandler` around `result()`. Remove it, because it is now a duplicate.
- State the behavior in the doc comment of `result()`.

## Acceptance Criteria
- [x] Cancelling a task that waits in `result()` cancels the run, and `result()` throws `CancellationError` soon after.
- [x] Cancelling the CLI start cancels the run.
- [x] A cancel of the slash command's stream still cancels the run (the existing test stays green).
- [x] `result()` with no cancel behaves as now.

## Tests
- [x] Cases in `Tests/FoundationModelsAgentsTests/AgentRunTests.swift` and `AgentsCLITests.swift`, with a gated scripted run.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.