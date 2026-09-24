---
assignees:
- claude-code
depends_on:
- 01M3A6CC94D147W0EXKNEBDKNA
- 01M3A6C3W4FTNNC249NNVFWH3M
- 01M3A6T9DJDWR2BXEA0AADPQR5
position_column: todo
position_ordinal: '8380'
title: A final-answer prompt when the last child ends
---
## What
In `Sources/FoundationModelsAgents/Run/AgentRun+Children.swift` `finishAfterChildren`, the parent's result is the text of its last delivery turn. When two children end at different times, there are two delivery turns. A real model replies to each post by itself, so the reply to the first post is lost from the result, and the model cannot know which turn is its last.

- When no child is open and no post is unread, and at least one delivery turn ran, enqueue one last prompt: "All agents that you started have finished. Give your full final answer." Then dispatch it.
- **The final-answer turn can start new children**, because the model still has the `agents` tool. After that turn, if a child is open, go on with the loop. When the loop is quiet again, send the final-answer prompt again. The text of the last final-answer turn is the result.
- A run that started no child is unchanged: its result is the text of its task turn.
- Each final-answer turn counts toward `maxTurns`, as each delivery turn does.
- Update plan.md §8 step 8 and the DocC article `RunningAnAgent.md`.

The extra turn changes each scripted play with children, because a play with no more steps throws `playExhausted`. Update these tests together with the code, so that the suite stays green: `NestedRunTests.swift`, `NestedRunTests+Limits.swift`, `MaxTurnsTests.swift` (the pass counts), `ReadmeExampleTests.swift`, and `AgentsDemoTests.swift`.

## Acceptance Criteria
- [ ] A parent with two children that end at different times gives a result that holds both child results, with a script that uses `.finalTextOfLastPrompt` (from `^aadpqr5`) in each delivery turn.
- [ ] A final-answer turn that starts a new child waits for that child, and the run ends only after one more final-answer turn.
- [ ] A run with no children gets no extra prompt.
- [ ] The extra turns are counted by `maxTurns`.

## Tests
- [ ] Change `NestedRunTests.leadJoinsBothResults` to the newest-prompt step, and add the cases for a new child in the final-answer turn and for a run with no children.
- [ ] Update the scripted plays in the five test files above.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.