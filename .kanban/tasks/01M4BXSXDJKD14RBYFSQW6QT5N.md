---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4c15tpnqc4vgnvhhk8b6k9t
  text: |-
    Implementation notes.

    - `RoutedSession.send(_:)` returns when the message is in the queue. It does not wait for the answer. Thus a `deliver` can start and end completely between the idle signal and the `endState` lock. With only the `inboundMessages == 0` check, the count is 0 again at that time, the run settles, and the message is lost. The test `messageBetweenIdleSignalAndSettleIsAnswered` showed this failure.
    - Fix: `Storage.acceptedMessages`, a count that only goes up (this is not a "closing" flag). The idle check reads it first (`acceptedMessagesWhenNoneInbound`, which is nil while a message is inbound). The `.idle` signal carries it (`AgentRunSignal.idle(_:acceptedMessages:)`). `settle(idle:acceptedMessages:)` sets `settled` in one lock, only when `inboundMessages == 0` and the count did not change. `.failed` and `.cancelled` still settle in `drive` and do not wait for the count.
    - `isIdle(on:)` is now `acceptedMessagesIfIdle(on:)`. It also requires `messageQueueDepth().running.isEmpty`. Without this, `deliveredInTaskTurn` failed: a message that waited during the task answer moved to `running` before the follower read its answer start, and the run ended with the task reply.
    - The test seams are `AgentRunIdleHooks` (`beforeIdleCheck`, `beforeIdleSettle`), set with `AgentRun.install(_:)` before `begin`. The race tests use them with `ScriptedGate`. They do not depend on timing.
    - The router has one generation queue for each model. In a test, a child that holds its answer at a gate on the same model as the parent also holds the answer of the parent to the message. `deliveredWhileWaitingForChildren` uses the reviewer as the child, because it runs on its own model.
  timestamp: 2026-10-07T20:34:15.381692+00:00
- actor: claude-code
  id: 01m4c15y04twbev4fx5776d43p
  text: |-
    ### implement — changed
    - evidence: 6 files. New: Sources/FoundationModelsAgents/Run/AgentRunMessageOutcome.swift, Tests/FoundationModelsAgentsTests/AgentRunMessageTests.swift. Changed: Sources/FoundationModelsAgents/Run/AgentRun.swift, Sources/FoundationModelsAgents/Run/AgentRun+Drive.swift, Sources/FoundationModelsAgents/Run/AgentRunAnswers.swift (AgentRunSignal.idle), Sources/FoundationModelsAgents/Tool/AgentsToolText.swift. Red first: the new tests did not compile, then the two race tests and deliveredInTaskTurn failed before the idle fixes. `swift test`: 439 tests in 64 suites passed. NestedRunTests+Idle did not change. The one build warning, "missing creator for mutated node ... mlx-swift_Cmlx.bundle", comes from the build of the mlx dependency, not from these files.
    - next: /review
  timestamp: 2026-10-07T20:34:18.756492+00:00
position_column: doing
position_ordinal: '80'
title: AgentRun accepts a message, or tells that it ended
---
## What
A caller must be able to send a message to a run that it started. The run must accept the message or tell that it ended. There must be no race with the idle rule.

Files:
- `Sources/FoundationModelsAgents/Run/AgentRun.swift`
- `Sources/FoundationModelsAgents/Run/AgentRun+Drive.swift`
- New: `Sources/FoundationModelsAgents/Run/AgentRunMessageOutcome.swift`
- `Sources/FoundationModelsAgents/Tool/AgentsToolText.swift` (the sender prefix)

Approach:
- Add `enum AgentRunMessageOutcome: Sendable, Equatable { case delivered; case ended(AgentRunState) }`.
- Add `func deliver(_ message: String) async -> AgentRunMessageOutcome` to `AgentRun`.
  - Under the `storage` lock, give `.ended(state)` in these cases:
    - `settled != nil` (the teardown started; `.ended(settled)`);
    - `isCancelRequested` (`.ended(.cancelled)`);
    - the run has no session (a setup failure).
  - Otherwise, increment a new `Storage.inboundMessages` count, and get the session.
  - Outside the lock: call `session.send(prefix + message)`, then decrement the count.
- Do not add a new "closing" flag. `Storage.settled` already marks the teardown.
- In `endState(after:on:)`, for the `.idle` signal: in one lock, check `inboundMessages == 0`, and set `settled`. If the count is not zero, return `nil`, so that the drive loop waits for the next event. A `.failed` or `.cancelled` end sets `settled` and does not wait for the count.
- `isIdle(on:)` (`AgentRun+Drive.swift:261`) also requires `messageQueueDepth().running.isEmpty`, and not only `waiting == 0`. Reason: the pump moves a taken message from `waiting` to `running` before the follower sees the start of the answer.
- The prefix `Message from your caller:` is one constant in `AgentsToolText`.
- The run limit: a message to a run in `.waitingForChildren` starts an answer with no check against `maxConcurrentAgents`. This is the same as an answer to mail. State this in the doc comment of `deliver`.

## Acceptance Criteria
- [ ] `deliver` on a running run gives `.delivered`, and the session answers the message before the run ends.
- [ ] `deliver` on a finished, failed or cancelled run, on a run with a cancel request, and on a setup failure gives `.ended` with the correct state.
- [ ] A message that `deliver` sends between the idle signal and `settle` is answered. The run does not end first.
- [ ] A message that the pump took (it is in `running`, and no answer start was read yet) keeps the run alive.
- [ ] The final message of the run is the reply of its last answer, as before.

## Tests
- [ ] New `Tests/FoundationModelsAgentsTests/AgentRunMessageTests.swift`, with `AgentRunHarness` and the scripted model:
  - delivered in the task turn;
  - delivered while the run waits for children;
  - ended after finish, cancel, cancel request and setup failure;
  - the two races above. Make each race deterministic with `ScriptedGate`, or with a test hook between the idle check and `settle`. The tests must not depend on timing.
- [ ] The existing tests in `NestedRunTests+Idle.swift` pass unchanged.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.