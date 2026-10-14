---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4x3h1wj654fbhthkqrqaenv
  text: 'Router part G is pushed: Router main head 18caf922 (part G is bc313dff). Move the Router pin to it after the T1 commit. T3 starts when T2 is done. Part H (awaitAnswer(of:)) is in progress.'
  timestamp: 2026-10-14T11:42:25.682473+00:00
depends_on:
- 01M4X3BB85J8JKMBXTYX0ZJQHD
position_column: todo
position_ordinal: '8380'
title: 'Mail step 3, T3: the idle rule by MailID (waits for Router part G)'
---
## Wait

Start only after the message that Router part G is pushed. Part G gives the MailID of each child message: the output events runMessage, runSettled, runProgress and elicitationRequested have the origin .mail([id]) of their run mail.

## Plan (from the step 3 message)

- ParentSessionWatch keeps the MailID of each child runMessage and runSettled, and the set of ids that have a terminal: answered.mailIds, answerFailed.mailIds, cancelled, lost. mailDelivered can come before or after the runMessage output event, so handle both orders.
- The session is idle when no answer is open, mailQueueDepth() is empty, each child run ended, and each child mail id and each caller mail id has a terminal.
- Remove isEachMessageDelivered(inAnsweredPrompts:), mailLine(of:), messageState, AgentRunAnswers.hasAnswered(promptHolding:in:), answeredPromptTexts and each other search of prompt text. The check of row 3: no code finds mail by text. pendingRunTokens(in:) decodes the pending envelopes of tool outputs to find runs that started before they are in children. Keep it only if no event gives the same fact, and say which choice you made.
- waitForSettlement(ofCalls:) stays (it is by token).
- Fixed-order tests with AgentRunIdleHooks: both orders of mailDelivered and runMessage; a message and the final result in one submission and in two; a child mail that cancelAll() cancels counts as a terminal; a caller message that arrives after the idle check.

## Decision G2 applies

"mailQueueDepth() is empty" means the user-type kinds only (user_message, agent_message, elicitation_answer are 0, running is empty). run_event in the depth is ignored; the run mail that matters is tracked by MailID here.

#mail-step-3