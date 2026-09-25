---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3cx4y71gwkbd2595sdnvch8
  text: |-
    Research:
    - The Router records the transcript diff (and sends `entryRecorded`) AFTER the model call of a turn ends. `runCancellableModelCall` states: "The turn's recording runs after this returns or throws and is never cancelled." Thus a `cancelCurrentTurn()` that the background counter sends after it sees an entry does not make that turn throw; the turn returns its text. The flag path (CancellationError -> hitMaxTurns) is correct, but with this Router revision it applies only when a cancel lands during a model call.
    - A turn with no `.response` in its diff gets a close `.response` in the recording file only (`append(partial:)`), not an `entryRecorded` event.
    - `streamSessionEvents()`: `close()` finishes each subscription, thus the follower task ends when the session closes.
    - Both the turn stream and each session subscription carry the open `toolInvocation` records. Thus with one run-long subscription, the task turn reads only text events from its own stream, else each tool name counts two times.
    - A settle from the transcript and a late background event can count one entry two times. Plan: the counter keeps `seen` (events) and `settled` (transcript count); the count is max(seen, settled).
    - Plan: `AgentRunTurns` holds the one counter, the limit flag, `follow(_:)`, `settle(passesIn:partial:)`, `deliver(...)` (closures over dispatch and transcript, so unit tests need no fake session), and `failure(for:partial:)`. `AgentRunProgress.passes` becomes a snapshot that `AgentRun.progress` fills from `turns.count`. The run also settles after the task turn, so the task-turn end state does not depend on the background task.
  timestamp: 2026-09-25T18:27:24.513422+00:00
- actor: claude-code
  id: 01m3cxjb36cfqy6fw9hddg2gp8
  text: |-
    Implementation notes:
    - One counter: `AgentRunTurns` (`Run/AgentRun+TurnLimit.swift`) keeps `seen` (events of the follower), `settled` (pass entries of the transcript at the last settle), and the limit flag. The count is max(seen, settled), thus a late event of a settled turn does not count two times. `AgentRunProgress.passes` is now a snapshot: `AgentRun.progress` sets it from `turns.count`. `AgentRunProgress.apply` no longer counts passes.
    - `startTurn` subscribes with `streamSessionEvents()` before the task turn. A task-group child runs `followPasses` (count + progress + `cancelCurrentTurn()` one time above the limit). The group body closes the session after `drive`, the close finishes the subscription, and the group waits for the child. Thus no task or subscription stays after the run ends.
    - `drive` no longer calls `turns.add`. `runTaskTurn` reads only the text events of the turn stream (the follower reads the tool records from the subscription, else each tool name counts two times), maps an error to `hitMaxTurns(partial: text so far)` when the flag is set, and settles the count from the transcript after the task turn. This settle after the task turn is an addition to the card text: without it, the end state of a task turn above the limit depends on the timing of the background task.
    - `dispatchCountingPasses(on:lastText:)` calls `turns.deliver`: dispatch, then settle from `session.transcript`. A cancel after the flag gives `hitMaxTurns(partial: text of the last complete turn)`. The old read-until-`.response` loop and the second per-turn subscription are removed.
    - Test location: the card names `MaxTurnsTests.swift`. With the new cases in that file, swiftlint reports file_length (427 > 400) and type_body_length (277 > 250). The new cases are in `MaxTurnsTests+Counter.swift` as `extension MaxTurnsTests { @Suite struct Counter }`, the same pattern as `AgentRunTests+Failures.swift`. The task-turn count case is in `MaxTurnsTests.swift` (`progress.passes == turns.count == 3`).
    - TDD: the counter cases failed first (compile: no `deliver`, `follow`, `failure`, `isLimitHit`, `add` with no `partial`). The task-turn "one time" case could not fail against the old code, because the old code had two separate counters; it guards the new run-long subscription.
    - plan.md §5 `maxTurns` text states the one counter, the settle after each turn, and the partial text.
  timestamp: 2026-09-25T18:34:43.686728+00:00
- actor: claude-code
  id: 01m3cxjf19v7sw0cmvhc24hz9m
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsAgents/Run/AgentRun+TurnLimit.swift, Sources/FoundationModelsAgents/Run/AgentRun.swift, Sources/FoundationModelsAgents/Run/AgentRun+Children.swift, Sources/FoundationModelsAgents/Run/AgentRunProgress.swift, Tests/FoundationModelsAgentsTests/MaxTurnsTests.swift, Tests/FoundationModelsAgentsTests/MaxTurnsTests+Counter.swift (new, 6 tests), Tests/FoundationModelsAgentsTests/AgentRunProgressTests.swift; plus plan.md §5. `swift build -Xswiftc -warnings-as-errors` complete; `swift test -Xswiftc -warnings-as-errors` 338 tests in 46 suites pass (3 runs); `cd IntegrationTests && swift build --build-tests` complete; swiftlint 0 violations in 119 files; periphery shows no finding in the changed files.
    - next: /review
  timestamp: 2026-09-25T18:34:47.721335+00:00
depends_on:
- 01M3A6BZSVQR5RJ7TNBJ0Z9Y9Q
position_column: doing
position_ordinal: '80'
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