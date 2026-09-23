---
assignees:
- claude-code
depends_on:
- 01M376HQNY14K766HPNACT3999
position_column: todo
position_ordinal: '9280'
title: 'maxTurns: count each model generation; hitMaxTurns'
---
## What
Plan.md §5 and §9.3, with this rule: **one turn is one model generation.** Each time the model generates in a run session (the generation that makes tool calls, each generation after tool results, and each generation of a delivery turn) the count goes up by one. Tool calls are not counted one by one: one generation that makes three tool calls counts as one.

Example: the task turn generates `Read`, then `Grep`, then two `start agent` calls, then text (4 generations); a delivery turn generates `Read`, then text (2); a second delivery turn generates text (1). The count is 7.

- Update §5 and §9.3 of `plan.md` to state this rule and remove the "counting decorator on tool calls" text.
- Create `Sources/FoundationModelsAgents/Run/AgentRun+TurnLimit.swift`: the run reads the `SessionEvent` stream of its session (the task turn and each `dispatchNextPrompt` turn). Each `entryRecorded` event with kind `.toolCalls` or `.response` is one generation. The Router has no event for one generation; this pair of kinds is the proxy. Write this in the doc comment.
- When the count goes above `maxTurns`, the run cancels its turn and fails with `AgentRunFailure.hitMaxTurns(partial: String)`, with the text of the turn so far. Open children are cancelled first (the nested-run rule). The failed run posts one `.completed` with the failure text.
- No `maxTurns` key: no limit.
- If the proxy does not give exactly one count for each generation (for example a generation that records both `.toolCalls` and `.response`), stop and add a Router task for a per-generation event. Do not guess.

## Acceptance Criteria
- [ ] A scripted generation that makes three tool calls counts as one.
- [ ] A generation that gives reasoning and a response counts as one.
- [ ] The run of the example above has a count of 7.
- [ ] `maxTurns: 2` with a script of three generations fails with `hitMaxTurns` and the partial text.
- [ ] `maxTurns: 3` with one task-turn generation and two delivery-turn generations succeeds; a fourth generation makes it fail.
- [ ] A run with no `maxTurns` and many generations succeeds.
- [ ] A `hitMaxTurns` run with an open child cancels the child first, then posts one `.completed`.
- [ ] `plan.md` §5 and §9.3 state the rule.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/MaxTurnsTests.swift` covers each criterion with `ScriptedProfile`.
- [ ] Run `swift test --filter MaxTurnsTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.