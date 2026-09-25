---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3da7qy4m70gggqdtyg2w749
  text: |-
    Research:
    - `finishAfterChildren` in `Run/AgentRun+Children.swift` loops: wait for an ending, then `dispatchCountingPasses`. The loop ends when no child was open and the dispatch ran no turn. The change adds one state: "a delivery turn ran since the last final-answer turn". When the loop is quiet and that state is true, the run enqueues the final-answer prompt with `session.enqueue(prompt:)` (a Router API that exists) and dispatches it through `dispatchCountingPasses`. Thus `maxTurns` counts it with no new code.
    - `NestedRunTests.parentPlay` is the one helper for the parent plays in `NestedRunTests`, `NestedRunTests+Limits`, and `AgentsDemoTests`. One final-answer step in the helper updates those plays. `NestedRunTests+Limits` needs no direct edit.
    - Other plays of a parent run that need a final-answer step: `MaxTurnsTests.finishedLead`, and `CheckAgentProgressTests.deliveryTurnGivesProgress` (not in the list of the task; it breaks without the step).
    - `ReadmeExampleTests` and the root plays of `AgentsDemoTests` are root sessions, not runs. The change does not touch them.
    - A play whose trailing delivery steps are all `.finalTextOfLaterPrompts` is correct for any count of delivery turns. Thus two children that can end in one delivery turn do not make a flaky play.
  timestamp: 2026-09-25T22:16:07.876924+00:00
- actor: claude-code
  id: 01m3daq30v1m3dmas72d9ph2q3
  text: |-
    Implementation landed (TDD: the new and changed tests failed first for the expected reasons, then passed).

    - Code: `AgentRun.finalAnswerPrompt` and `dispatchFinalAnswer(on:lastText:)` in `Run/AgentRun+Children.swift`. `finishAfterChildren` keeps one flag, `isFinalAnswerDue`, that a delivery turn sets. When the loop is quiet and the flag is set, the run queues the prompt with `session.enqueue(prompt:)` and dispatches it through `dispatchCountingPasses`, so `maxTurns` counts it. No Router change.
    - Tests: `NestedRunTests.leadJoinsBothResults` uses `.finalTextOfLastPrompt` in each delivery turn. A gate on code-reviewer, and a wait for the first delivery prompt, make the two children end in two delivery turns. New file `NestedRunTests+FinalAnswer.swift` holds the case for a new child in the final-answer turn and the case for a run with no children. New `MaxTurnsTests.finalAnswerPassAboveLimitFails` (an agent with `maxTurns: 3` fails in its final-answer turn). `leadPasses` is now 4.
    - Scripted plays: `NestedRunTests.parentPlay` now ends with `finalAnswerStep`. That one helper updates the parent plays of `NestedRunTests`, `NestedRunTests+Limits`, and `AgentsDemoTests`, so these two files need no direct edit. `MaxTurnsTests.finishedLead` and `CheckAgentProgressTests.deliveryTurnGivesProgress` (not on the list, but it failed without the step) got a final-answer step. `ReadmeExampleTests` needs no change: its play is a root session, not a run, and the change does not touch root sessions.
    - Docs: plan.md §5, §8 step 8, §9.3, and the test list; `RunningAnAgent.md`, `TheFinalMessage.md`, `DelegatingWithTheAgentsTool.md`; doc comments in `AgentRun.swift`, `AgentRun+TurnLimit.swift`, `AgentRunFailure.swift`, `AgentRunner.swift`.
    - Not changed: `AgentRunProgress` still shows the phase "a delivery turn" during a final-answer turn. `AgentRunPhase.delivery` now states that it covers both turn kinds.
    - Stability: 8 more runs of the affected suites were all green.
  timestamp: 2026-09-25T22:24:30.747154+00:00
- actor: claude-code
  id: 01m3daq5js90kr0x299g29edkx
  text: |-
    ### implement — changed
    - evidence: 14 files. Sources/FoundationModelsAgents/Run/AgentRun+Children.swift, AgentRun+TurnLimit.swift, AgentRun.swift, AgentRunFailure.swift, AgentRunner.swift; docc RunningAnAgent.md, TheFinalMessage.md, DelegatingWithTheAgentsTool.md; plan.md; Tests NestedRunTests.swift, NestedRunTests+FinalAnswer.swift (new), MaxTurnsTests.swift, CheckAgentProgressTests.swift. `swift build -Xswiftc -warnings-as-errors`: ok. `swift test -Xswiftc -warnings-as-errors`: 351 tests in 48 suites passed. `cd IntegrationTests && swift build --build-tests`: ok. swiftlint: 0 violations in 122 files.
    - next: /review
  timestamp: 2026-09-25T22:24:33.369324+00:00
- actor: claude-code
  id: 01m3daz5x3h2kg908723gs0dy8
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (0fbdd16): 0 findings (7 validator runs attempted, 0 failed, 0 skipped). 9 files reviewed. The .kanban files are excluded by .reviewignore. No validator matches plan.md and the three DocC articles.
    - next: none. The task moved to done.
  timestamp: 2026-09-25T22:28:55.843381+00:00
- actor: claude-code
  id: 01m3dazd5phpyh4ykjrf0n8jjd
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 14 files
    - test: green — swift test -Xswiftc -warnings-as-errors, 351 passed; swiftlint 0; IntegrationTests build --build-tests passes
    - commit: 0fbdd16
    - review: clean — 0 findings
  timestamp: 2026-09-25T22:29:03.286341+00:00
depends_on:
- 01M3A6CC94D147W0EXKNEBDKNA
- 01M3A6C3W4FTNNC249NNVFWH3M
- 01M3A6T9DJDWR2BXEA0AADPQR5
position_column: done
position_ordinal: a980
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
- [x] A parent with two children that end at different times gives a result that holds both child results, with a script that uses `.finalTextOfLastPrompt` (from `^aadpqr5`) in each delivery turn.
- [x] A final-answer turn that starts a new child waits for that child, and the run ends only after one more final-answer turn.
- [x] A run with no children gets no extra prompt.
- [x] The extra turns are counted by `maxTurns`.

## Tests
- [x] Change `NestedRunTests.leadJoinsBothResults` to the newest-prompt step, and add the cases for a new child in the final-answer turn and for a run with no children.
- [x] Update the scripted plays in the five test files above.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.