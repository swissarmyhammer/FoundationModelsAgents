---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
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
- [ ] `check agent` on a run in its task turn gives the phase, the pass count, the last tool names, and the text tail.
- [ ] During a delivery turn it shows the delivery phase, the new passes and tool names; the text tail updates when the delivery turn returns.
- [ ] `check agent` returns at once while the run's turn holds the model (a gated scripted turn).
- [ ] `AgentRunActivity` no longer exists.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentRunProgressTests.swift`: the text of the record for each phase; the tool-name and text-tail limits.
- [ ] Update `AgentsToolOperationsTests` and `NestedRunTests`; delete `AgentRunActivityTests`.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.