---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3802mjm4s5c2mfyn512pss8
  text: |-
    Research (implement):
    - The Router emits `entryRecorded` from the turn diff at the END of each Router turn (RoutedSessionActorRecording.recordTranscriptDelta). Each event goes to the turn sink AND to each `streamSessionEvents()` subscription (RoutedSessionActorTurnExecution.turnEventSink). This is true for `dispatchNextPrompt()` turns too.
    - Thus the passes of a delivery turn are visible with no Router change: open `session.streamSessionEvents()` before `dispatchNextPrompt()`. When the dispatch gives text, all events of that turn are already in the buffer. Read them until the `entryRecorded(.response)` of the answer pass. A cancel of the run ends the read.
    - The task turn counts from its own `streamEvents` stream. A throw in the loop abandons the stream, and that cancels the turn.
    - `turnEnded` is not a safe end marker: the Router emits it only when the backend reports usage, and the scripted backend meters nothing.
    - The cleanup in `startTurn` already cancels open children, waits, closes, and posts one `.completed`. A `hitMaxTurns` throw only has to reach `drive`'s catch.
  timestamp: 2026-09-23T20:42:22.676036+00:00
- actor: claude-code
  id: 01m380bm4w7wf26vs38m6rcrtd
  text: |-
    ### implement — changed
    - evidence: 8 files — Sources/FoundationModelsAgents/Run/AgentRun+TurnLimit.swift (new: AgentRunTurns, dispatchCountingPasses(on:)), Run/AgentRun.swift (turns, count in the task-turn stream loop), Run/AgentRun+Children.swift (delivery turns go through dispatchCountingPasses), Run/AgentRunFailure.swift (hitMaxTurns(partial:), reason, turnFailure keeps an AgentRunFailure), Tests/.../MaxTurnsTests.swift (new, 7 tests), Tests/.../Support/ScriptedAgentModel.swift (new step repeatedToolCall: many calls in one .toolCalls entry; step switch split for complexity), Tests/.../AgentBodyRendererTests.swift (switch case .hitMaxTurns).
    - `swift test --filter MaxTurnsTests`: 7/7 pass. swiftlint: 0. build -warnings-as-errors: clean.
    - No Router change. The delivery-turn passes come from `streamSessionEvents()`, opened before `dispatchNextPrompt()`.
    - next: test
  timestamp: 2026-09-23T20:47:17.148084+00:00
- actor: claude-code
  id: 01m380cs1rghzq9ajwn25ed1w8
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 234 tests in 31 suites passed, 0 failed, 0 skipped; swiftlint lint --quiet Sources Tests Examples — 0 violations
    - next: commit
  timestamp: 2026-09-23T20:47:54.936759+00:00
depends_on:
- 01M376HQNY14K766HPNACT3999
position_column: doing
position_ordinal: '80'
title: 'maxTurns: count each pass through the tool loop; hitMaxTurns'
---
## What
Plan.md §5 and §9.3. **One turn is one pass through the control loop.** In each pass the model generates, and then it calls tools (and the loop goes around again) or it answers (and the loop ends). All passes of the run count, in the task turn and in each delivery turn. No Router change.

- Each pass records one transcript entry: `.toolCalls` or `.response`. The Router emits `SessionEvent.entryRecorded(id:kind:)` for each entry.
- Create `Sources/FoundationModelsAgents/Run/AgentRun+TurnLimit.swift`: the run reads the event stream of each of its turns and adds one to its count for each `entryRecorded` with kind `.toolCalls` or `.response`.
- When the count goes above `maxTurns`, the run cancels its turn and fails with `AgentRunFailure.hitMaxTurns(partial: String)`, with the text so far. Open children are cancelled first (the nested-run rule). The failed run posts one `.completed` with the failure text.
- No `maxTurns` key: no limit.

## Acceptance Criteria
- [ ] A task turn with two tool passes and one answer counts 3.
- [ ] One pass that calls three tools counts 1.
- [ ] `maxTurns: 2` with a script of three passes fails with `hitMaxTurns` and the partial text.
- [ ] Passes in delivery turns add to the same count.
- [ ] A run with no `maxTurns` finishes with any number of passes.
- [ ] A `hitMaxTurns` run with an open child cancels the child first, then posts one `.completed`.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/MaxTurnsTests.swift` covers each criterion with `ScriptedProfile`.
- [ ] Run `swift test --filter MaxTurnsTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.