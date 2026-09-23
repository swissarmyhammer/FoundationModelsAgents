---
assignees:
- claude-code
depends_on:
- 01M376HQNY14K766HPNACT3999
position_column: todo
position_ordinal: '9280'
title: 'maxTurns: count each pass through the tool loop; hitMaxTurns'
---
## What
Plan.md §5 and §9.3. **One turn is one pass through the tool loop.** In each pass the model generates, and then it calls tools (and the loop goes around again) or it answers (and the loop ends). All passes of the run count, in the task turn and in each delivery turn.

- Update §5 and §9.3 of `plan.md` to state this rule and remove the "counting decorator on tool calls" text.
- The loop runs inside the FoundationModels session. Each pass records one transcript entry: `.toolCalls` or `.response`. The Router emits `SessionEvent.entryRecorded(id:kind:)` for each entry.
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
- [ ] `plan.md` §5 and §9.3 state the rule.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/MaxTurnsTests.swift` covers each criterion with `ScriptedProfile`.
- [ ] Run `swift test --filter MaxTurnsTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.