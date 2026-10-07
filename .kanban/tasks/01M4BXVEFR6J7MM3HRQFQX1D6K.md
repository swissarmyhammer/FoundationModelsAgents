---
assignees:
- claude-code
depends_on:
- 01M4BXV22HHY1EYE8XEVSV23GW
position_column: todo
position_ordinal: '8480'
title: A parent run does not end before it answers each message mail of a child
---
## What
A child can send a message and then end at once. The parent run must answer that message mail before the idle rule lets it end. The parent must not miss the message.

Files:
- `Sources/FoundationModelsAgents/Run/ParentSessionWatch.swift`: record each `SessionEvent.runMessage(OperationEvent)` in an ordered list for each `correlationID`, next to the `.runSettled` details (:50-113). One child can send many messages with the same token, so do not key one message by token.
- `Sources/FoundationModelsAgents/Run/AgentRun+Drive.swift`:
  - Do an idle check after `.runMessage` as well as after `.runSettled` (:197-237).
  - `isIdle(on:)` (:261) gives `false` while a recorded message is not in a prompt that a later answer replied to. This is the same rule as for the pending envelopes.
- `Sources/FoundationModelsAgents/Run/AgentRunProgress.swift`:
  - `check agent` on a parent shows the last message of each running child as the last event of that child: `message: <first line of the text>`.
  - While a run answers a caller message or a child message, its phase is `answeringMail`.

Rules:
- The Router puts the message mail and a settled terminal of the same child in one submission, or in two, in outbox order. Both orders must work.
- Message mail counts toward `mailOnlyAnswerLimit`. When the Router pauses delivery (`.mailDeliveryPaused`), the parent run fails with the existing `hitMaxTurns`/paused handling, the same as for final-message mail. It does not hang.

## Acceptance Criteria
- [ ] A child that calls `send caller` and then ends at once: the parent answers the message mail and the final message, and only then ends. The final message of the parent is the reply of its last answer.
- [ ] A child that sends two messages: the parent answers both before it ends.
- [ ] A child that sends a message while the parent is in its task turn: the message waits until that answer ends, and then the parent answers it.
- [ ] `check agent` on the parent shows `message: <text>` for the child.
- [ ] A child that sends more messages than `mailOnlyAnswerLimit` makes the parent end with the paused outcome, not hang.

## Tests
- [ ] New `Tests/FoundationModelsAgentsTests/NestedRunTests+Messages.swift` with the scripted model:
  - the first three criteria above;
  - the two delivery orders;
  - the `mailOnlyAnswerLimit` case.
- [ ] Add a progress-view test to `Tests/FoundationModelsAgentsTests/AgentRunProgressTests.swift`.
- [ ] Live test in `IntegrationTests/Tests/AgentsIntegrationTests/LiveNestedTests.swift`: a parent starts a child whose prompt tells it to send one progress message to its caller and then finish. Assert that the parent transcript has a `.runMessage` and that the parent finishes.
- [ ] `swift test` passes. The integration package `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.