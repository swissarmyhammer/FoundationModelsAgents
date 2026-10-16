---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53jg8ppmdtsd34q154b95k2
  text: |-
    ### done
    - commit 82bf55b: `answersQuestions: relay == nil`, the doc comments, and the hook `AgentRunIdleHooks.afterQuestion`.
    - Test `headlessTargetGuardAnswersQuestion` (AgentRunQuestionTests): before the fix it failed with 2 issues (the answer of the test was delivered) and did not hang; after the fix the suite passed (5 tests).
    - One full run: 583 tests in 80 suites passed.
  timestamp: 2026-10-16T23:59:35.126055+00:00
position_column: done
position_ordinal: e980
title: 'Group D: a run with a headless question target must answer questions itself'
---
Source: elicitation-plan.md section 10, the check of 2026-10-16.

`AgentRun.drive` (Run/AgentRun+Drive.swift:104) sets `answersQuestions: questionTarget == nil`. When the target is headless, the run starts no relay, and it also does not answer questions itself. `answerQuestion(of:on:)` (lines 363-374) is a guard for a session that is interactive by a different path. For such a session with a headless target, a question waits forever.

Fix: set `answersQuestions: relay == nil`.

- [ ] A test fails before the fix: a run with a headless target and an interactive session gets a question. The question must end with the cancel of `RunPlane.noUserPresentReason`. The test waits also on the failure event, thus it does not hang before the fix.
- [ ] The fix: `answersQuestions: relay == nil`, and the doc comments agree.
- [ ] One full run is green. #elicitation-check #bug