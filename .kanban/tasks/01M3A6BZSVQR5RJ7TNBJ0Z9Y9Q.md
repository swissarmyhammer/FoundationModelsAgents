---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3c9vk3ydnx5cbmfdnr9t4x8
  text: |-
    Research:
    - `AgentRun.Storage` holds `lastEvent` (from `AgentRunActivity.phrase`) and `phase`. `report(of:)` in `AgentRun+FinalMessage.swift` gives "is running: lastEvent" plus `waitingSentence`.
    - The task turn reads `session.streamEvents(to:)` in `drive`. The delivery turn (`dispatchCountingPasses` in `AgentRun+TurnLimit.swift`) reads its `streamSessionEvents()` subscription only AFTER `dispatchNextPrompt()` returns. Thus a live view of a delivery turn needs a second subscription that a child task reads while the dispatch runs. The pass count of `AgentRunTurns` stays as it is (^cc94d14 changes it); the progress record keeps its own live pass count.
    - `SessionEvent` has no library evolution: use `if case`, no `default:`.
    - The swift validators forbid a leaked unstructured `Task {}`: the delivery follower runs as a child in a task group.
    - Plan: `AgentRunProgress` (phase, passes, last tool names, text tail) in `Run/AgentRunProgress.swift`; phase moves into it. Report text: "Agent x (id) is running." + optional waiting sentence, then the lines of the record.
  timestamp: 2026-09-25T12:50:15.294444+00:00
- actor: claude-code
  id: 01m3ca99q5k80dzzjgpnqj5v98
  text: |-
    Discovery (Router behavior): `SessionEvent.toolCall` and `SessionEvent.entryRecorded` come from the transcript diff in `RoutedSessionActor.finishTurn` / `recordTranscriptDelta`, which runs when the turn ends. Thus they do NOT arrive while a gated turn holds the model. The first run-level tests (poll for passes >= 1 at the gate) timed out for this reason. The live mid-turn signals are text deltas (task turn only) and `SessionEvent.toolInvocation(record)`: every mounted tool is wrapped (`ToolMounting.makeWrapped`), and each call posts an open record (`closedAt == nil`) through `deliverLive` to the turn stream AND to each `streamSessionEvents()` subscription.
    Decision inside the card: the record takes tool names from open `toolInvocation` records (live), and ignores `toolCall` (the diff would add each name a second time). Passes come from `entryRecorded`, so the pass count updates when each turn ends. A live pass count mid-turn needs a Router change; it is not in this card.
  timestamp: 2026-09-25T12:57:44.421650+00:00
- actor: claude-code
  id: 01m3caw28crgjpf9tvek2gvmc9
  text: |-
    ### implement — changed
    - evidence: `swift build -Xswiftc -warnings-as-errors` complete; `swift test -Xswiftc -warnings-as-errors` 326 tests in 45 suites pass; swiftlint 0 violations; periphery shows no finding in the changed files.
    - files: new `Sources/FoundationModelsAgents/Run/AgentRunProgress.swift`, `Tests/FoundationModelsAgentsTests/AgentRunProgressTests.swift` (8 tests), `Tests/FoundationModelsAgentsTests/CheckAgentProgressTests.swift` (2 gated run tests); changed `Run/AgentRun.swift` (progress in `Storage`, `progress`, `record(_:)`, `recordDelivered(_:)`; phase moves into the record), `Run/AgentRun+FinalMessage.swift` (`report(of:)` for `.running`), `Run/AgentRun+TurnLimit.swift` (`dispatchFollowingProgress(on:)`: a task-group child reads a second session-event subscription while `dispatchNextPrompt()` runs), `AgentsToolOperationsTests.swift`, `NestedRunTests.swift`; deleted `Run/AgentRunActivity.swift` and `AgentRunActivityTests.swift`.
    - report text of a running run: "Agent x (id) is running." [+ " It waits for N agents that it started."], then "Phase: ...", "Passes: N.", "Last tools: a, b.", "Text so far: ..." (cut mark "..." when the tail is cut). Limits: 5 tool names, 240 characters.
    - limit (Router): passes count when the Router records the entries, which is at the end of each turn. Tool names are live (open `toolInvocation` records). See the discovery comment.
    - not done here by the card: plan.md §9.1 row (^nvfwh3m).
    - next: /review
  timestamp: 2026-09-25T13:07:59.372401+00:00
- actor: claude-code
  id: 01m3cjdprr1yj3h76sdskkjccg
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (2738ef7). 0 findings (confirmed 0, refuted 0, attempted 7, failed 0). The engine reviewed 10 files and did not review 2 files in .kanban/ because of .reviewignore. The tool rules did not read the two deleted files AgentRunActivity.swift and AgentRunActivityTests.swift, because those files are not there.
    - next: none. The task moved to done.
  timestamp: 2026-09-25T15:19:57.464610+00:00
- actor: claude-code
  id: 01m3cjdyhe58vm3hseyymk7kd9
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 10 files
    - test: green — swift test -Xswiftc -warnings-as-errors, 326 passed; swiftlint 0
    - commit: 2738ef7 (8f6aa9f removes trailing commas in Package.swift)
    - review: clean — 0 findings
  timestamp: 2026-09-25T15:20:05.422343+00:00
position_column: done
position_ordinal: a180
title: 'check agent: a non-blocking progress view from the run''s live transcript'
---
## What
`check agent` on a running run gives only "is running: `lastEvent`", and `lastEvent` is not updated during a delivery turn. Make it a real, non-blocking progress view of the run.

- Keep a live progress record on `AgentRun`, in its `Mutex` storage: the phase, the count of passes, the names of the last tool calls (a small fixed number), and the tail of the text so far (cut to a fixed number of characters).
- Feed it from the streams that the run already reads:
  - the task turn: the `streamEvents` loop in `AgentRun.drive` (tool calls, text deltas, text resets, recorded entries);
  - delivery turns: `streamSessionEvents()` carries tool and entry events but **no text deltas**. The text tail of a delivery turn is set from the text that `dispatchNextPrompt()` gives when it returns.
- Do not read `transcript.jsonl` (the guard tests forbid file I/O in `Sources`). Do not read `RoutedSession.transcript` while a turn runs (it waits for the turn lock).
- Create `Sources/FoundationModelsAgents/Run/AgentRunProgress.swift` (the record and its text), and change `Run/AgentRun+FinalMessage.swift` `report(of:)` for `.running`. **Remove `AgentRunActivity`** and its tests; the progress record replaces it.
- The answer for a finished, failed, or cancelled run does not change.
- Plan.md §9.1 (the `check agent` row) changes in `^nvfwh3m`.

Test files change together with the code, so that the suite stays green: `AgentsToolOperationsTests.swift`, `NestedRunTests.swift` (the `is running:` prefix check), and `AgentRunActivityTests.swift` (delete).

## Acceptance Criteria
- [x] `check agent` on a run in its task turn gives the phase, the pass count, the last tool names, and the text tail.
- [x] During a delivery turn it shows the delivery phase, the new passes and tool names; the text tail updates when the delivery turn returns.
- [x] `check agent` returns at once while the run's turn holds the model (a gated scripted turn).
- [x] `AgentRunActivity` no longer exists.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/AgentRunProgressTests.swift`: the text of the record for each phase; the tool-name and text-tail limits.
- [x] Update `AgentsToolOperationsTests` and `NestedRunTests`; delete `AgentRunActivityTests`.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.