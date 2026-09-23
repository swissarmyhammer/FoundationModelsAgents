---
assignees:
- claude-code
depends_on:
- 01M376HQNY14K766HPNACT3999
position_column: todo
position_ordinal: '9280'
title: 'maxTurns: count Router turns; hitMaxTurns'
---
## What
Plan.md §5 and §9.3. **One turn is one pass through the Router loop:** the task turn (`session.streamEvents(to: prompt)`) and each delivery turn (`session.dispatchNextPrompt()`). Tool calls and generations inside a turn are not counted.

- Update §5 of `plan.md` to state this rule and remove the "counting decorator on tool calls" text.
- In `Sources/FoundationModelsAgents/Run/AgentRun+Children.swift` (the delivery loop), before each delivery turn, add one to the count of the run. The task turn is turn 1.
- When the next turn would go above `maxTurns`, the run does not start it. It fails with `AgentRunFailure.hitMaxTurns(partial: String)`, with the text of the last turn. Open children are cancelled first (the nested-run rule). The failed run posts one `.completed` with the failure text.
- No `maxTurns` key: no limit.

## Acceptance Criteria
- [ ] `maxTurns: 1`: a run with no children finishes normally.
- [ ] `maxTurns: 1`: a run whose child finishes fails with `hitMaxTurns` instead of a delivery turn, and the partial text is the text of the task turn.
- [ ] `maxTurns: 3`: a task turn and two delivery turns succeed.
- [ ] A turn with many tool calls counts as one.
- [ ] A `hitMaxTurns` run with an open child cancels the child first, then posts one `.completed`.
- [ ] `plan.md` §5 states the rule.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/MaxTurnsTests.swift` covers each criterion with `ScriptedProfile`.
- [ ] Run `swift test --filter MaxTurnsTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.