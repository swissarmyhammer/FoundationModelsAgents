---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4c9rz825dtpfj3g4s2c81r4
  text: |-
    Research (picked up, moved to doing):
    - The idle check is now `acceptedMessagesIfIdle(on:)` in AgentRun+Drive.swift (the card names it `isIdle(on:)`). It reads the pending envelopes, the settled details in ParentSessionWatch, and `AgentRunAnswers.hasAnswered(promptHolding:in:)`.
    - Router 5713abe: a `.message` OperationEvent is journaled as a `.toolOutput` entry and goes live as `SessionEvent.runMessage`. The pump renders it in the prompt as `[tool] op (token) message, still running: detail` (OperationEventSegment.renderedLine). `takeEvents()` takes all mail for a caller-message submission and for each continuation submission, thus message mail can also ride the task answer or a caller-message answer.
    - The outbox keeps message mail before the terminal of the same child. Thus the envelope rule already keeps the parent until the message is answered in most orders. The new message rule is a direct check that does not depend on that order.
    - One child can send the same text two times with one token. The rule counts the rendered mail line in the answered prompts; it does not use a contains check.
    - `mailOnlyAnswerLimit` is a SessionConfiguration value (default 100). AgentSessionMaker uses `makeSession(instructions:...)`, which has no limit parameter. The paused-outcome test needs a small limit, thus AgentEnvironment gets an internal `mailOnlyAnswerLimit` that AgentSessionMaker passes in a SessionConfiguration. This is plumbing for the test of the card; the public API does not change.
    - A child needs an agents tool with a caller link to call `send caller`. The fixture children (code-reviewer, test-writer) have none (^m6x4er6 adds it later). The new suite uses a temporary layer: a parent with `tools: Agent` on standard, and a child with `model: flash` and `tools: Agent`, thus the parent can answer while the child waits on a gate.
    - Live models (Qwen3-4B-4bit, Qwen3-1.7B-4bit) are in the local HF cache, thus the live test can run here.
  timestamp: 2026-10-07T23:04:31.234928+00:00
- actor: claude-code
  id: 01m4cam7tjgtz5c7dh7j8wehwm
  text: |-
    Implementation landed (not committed).
    - ParentSessionWatch keeps each `runMessage` in an ordered list for each token. `isEachMessageDelivered(inAnsweredPrompts:)` counts the Router mail line `[tool] op (token) message, still running: detail` in the answered prompts, thus two equal messages need two lines.
    - AgentRunAnswers has `answeredPromptTexts(in:)`; `hasAnswered(promptHolding:in:)` now uses it.
    - AgentRun+Drive: an idle check after `.runMessage` as well as after `.runSettled` (`idleSignalAfterRunEvent(on:)`), and `acceptedMessagesIfIdle(on:)` also needs each child message delivered.
    - AgentRunProgress: one line `Last event of <token>: message: <first line>` for each running child that sent a message, before `Text so far`. The settlement of the child removes the line. The phase rule already gave `answeringMail` for answers after the task answer; only the doc comment of the case changed. The phase text stays "an answer to a final message" because plan.md §9.1 states it; ^TP66 (documents) can change both.
    - AgentEnvironment has an internal `mailOnlyAnswerLimit` (default `SessionConfiguration.defaultMailOnlyAnswerLimit`). AgentSessionMaker now makes the session with `makeSession(configuration:)` and passes it. The public API did not change.
    - Test support: `TemporaryLayer.make(holding:)` is shared; NestedRunTests+Limits uses it, the new suite too. AgentRunHarness `environment`/`makeRunner` take `mailOnlyAnswerLimit`.

    TDD record: RED for the progress line (AgentRunProgressTests), for the message rule (ParentSessionWatchTests, missing API), for `answeredPromptTexts` (AgentRunAnswersTests) and for the limit plumbing (missing `AgentEnvironment.mailOnlyAnswerLimit`). After the plumbing only, the six scripted tests of NestedRunTests+Messages passed before the Drive change: the Router outbox keeps message mail before the terminal of the same child, and the envelope rule then holds the parent. Thus the Drive wiring is a direct check that does not depend on that order; no scripted order makes the old rule end early.

    Live test: the small flash model sometimes changes the text of the message (one run sent "MANGO"). The live test asserts that a message was posted and read in a prompt of the parent, and that the parent finished; it does not assert the words.

    The build prints `warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)` from the SwiftPM build system for the mlx-swift dependency bundle. It is not a compiler warning of the changed code.
  timestamp: 2026-10-07T23:19:24.754669+00:00
- actor: claude-code
  id: 01m4camb4k9m9xjqd5prb6tcbm
  text: |-
    ### implement — changed
    - evidence: 17 files — Sources/FoundationModelsAgents/Run/{ParentSessionWatch,AgentRun+Drive,AgentRunProgress,AgentRunAnswers,AgentRun+Children,AgentEnvironment,AgentSessionMaker}.swift; Tests/FoundationModelsAgentsTests/{NestedRunTests+Messages (new),ParentSessionWatchTests (new),AgentRunProgressTests,AgentRunAnswersTests,NestedRunTests+Limits,Support/AgentRunHarness,Support/TemporaryLayer}.swift; IntegrationTests/Tests/AgentsIntegrationTests/LiveNestedTests.swift. `swift test`: 483 tests in 68 suites passed. `swift build --package-path IntegrationTests --build-tests`: complete. `swift test --package-path IntegrationTests`: 13 tests in 6 suites passed (live models on this machine), including the new live message test.
    - next: /review
  timestamp: 2026-10-07T23:19:28.147378+00:00
depends_on:
- 01M4BXV22HHY1EYE8XEVSV23GW
position_column: doing
position_ordinal: '80'
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
- [x] A child that calls `send caller` and then ends at once: the parent answers the message mail and the final message, and only then ends. The final message of the parent is the reply of its last answer.
- [x] A child that sends two messages: the parent answers both before it ends.
- [x] A child that sends a message while the parent is in its task turn: the message waits until that answer ends, and then the parent answers it.
- [x] `check agent` on the parent shows `message: <text>` for the child.
- [x] A child that sends more messages than `mailOnlyAnswerLimit` makes the parent end with the paused outcome, not hang.

## Tests
- [x] New `Tests/FoundationModelsAgentsTests/NestedRunTests+Messages.swift` with the scripted model:
  - the first three criteria above;
  - the two delivery orders;
  - the `mailOnlyAnswerLimit` case.
- [x] Add a progress-view test to `Tests/FoundationModelsAgentsTests/AgentRunProgressTests.swift`.
- [x] Live test in `IntegrationTests/Tests/AgentsIntegrationTests/LiveNestedTests.swift`: a parent starts a child whose prompt tells it to send one progress message to its caller and then finish. Assert that the parent transcript has a `.runMessage` and that the parent finishes.
- [x] `swift test` passes. The integration package `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.