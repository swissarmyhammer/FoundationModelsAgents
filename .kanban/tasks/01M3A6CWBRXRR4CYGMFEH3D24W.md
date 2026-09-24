---
assignees:
- claude-code
depends_on:
- 01M3A6BZSVQR5RJ7TNBJ0Z9Y9Q
position_column: todo
position_ordinal: '8580'
title: result() cancels the run when the waiting task is cancelled
---
## What
`AgentRun.result()` (`Sources/FoundationModelsAgents/Run/AgentRun.swift`) waits on `finalState()`, which awaits `turn.value` and ignores the cancel of the task that waits. Example: in the README fan-out, `async let a = runner.start(...).result()`. A throw in the sibling cancels `a`, but the host still waits for the whole run of `a`, and the run goes on.

- Wrap the wait of `result()` in `withTaskCancellationHandler { … } onCancel: { run.cancel() }`. Then `result()` throws `CancellationError` when the run ends as cancelled.
- The CLI start (`CLI/AgentsCLIOperations.swift`) already returns `try await run.result()`, so it gets the fix through `result()`.
- `Commands/AgentRunner+SlashCommands.swift` `finalText(ofAgent:)` has its own `withTaskCancellationHandler` around `result()`. Remove it, because it is now a duplicate.
- State the behavior in the doc comment of `result()`.

## Acceptance Criteria
- [ ] Cancelling a task that waits in `result()` cancels the run, and `result()` throws `CancellationError` soon after.
- [ ] Cancelling the CLI start cancels the run.
- [ ] A cancel of the slash command's stream still cancels the run (the existing test stays green).
- [ ] `result()` with no cancel behaves as now.

## Tests
- [ ] Cases in `Tests/FoundationModelsAgentsTests/AgentRunTests.swift` and `AgentsCLITests.swift`, with a gated scripted run.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.