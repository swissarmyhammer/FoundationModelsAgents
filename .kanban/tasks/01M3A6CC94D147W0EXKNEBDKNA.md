---
assignees:
- claude-code
depends_on:
- 01M3A6BZSVQR5RJ7TNBJ0Z9Y9Q
position_column: todo
position_ordinal: '8280'
title: 'One pass counter for all turns: exact after each delivery turn, with a limit that ends as hitMaxTurns'
---
## What
`dispatchCountingPasses(on:)` in `Sources/FoundationModelsAgents/Run/AgentRun+TurnLimit.swift` opens `streamSessionEvents()` for each delivery turn and reads until one `entryRecorded(.response)` event. It has no other exit. A turn with no `.response` entry hangs the parent (and then its caller and children). A turn that retries after an overflow records two `.response` entries, so the count is too low.

Change it:
- **One counter for all turns.** Open one `streamSessionEvents()` subscription for each run when the session is made. It carries the `entryRecorded` events of every turn, the task turn too. A background task counts each `entryRecorded(.toolCalls | .response)` and feeds the progress record of `^j0z9y9q`. Remove `turns.add` from `AgentRun.drive`, so the task turn is not counted two times.
- **Exact after each delivery turn.** The background task can be behind the stream when `dispatchNextPrompt()` returns. After each dispatch returns, set the count from the `.toolCalls` and `.response` entries of `session.transcript` (the turn lock is free at that point). Then check the limit.
- **Stop during a turn.** When the background count goes above `maxTurns` during a turn, the run sets a "limit hit" flag and calls `session.cancelCurrentTurn()`.
- **The end state.** After the cancel, `streamEvents` or `dispatchNextPrompt()` throws `CancellationError`. `drive` and `finishAfterChildren` read the flag and give `.failed(.hitMaxTurns(partial:))`, not `.cancelled`. The partial text is the text so far of the task turn, or, in a delivery turn, the text of the last complete turn (the session stream has no text deltas).
- The background task ends when the session closes.

## Acceptance Criteria
- [ ] A delivery turn that records no `.response` entry does not hang the run.
- [ ] A delivery turn with two `.response` entries (a retry) counts both passes.
- [ ] The count is exact at once after a delivery turn returns.
- [ ] Each pass of the task turn is counted one time, not two.
- [ ] A run above `maxTurns` in a task turn or a delivery turn ends as `.failed(.hitMaxTurns)` with the stated partial text, never as `.cancelled`.
- [ ] No task or subscription stays after the run ends.

## Tests
- [ ] Cases in `Tests/FoundationModelsAgentsTests/MaxTurnsTests.swift`: no `.response` in a delivery turn; a retry; the exact count after a delivery turn; the end state in each kind of turn; the task-turn count.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.