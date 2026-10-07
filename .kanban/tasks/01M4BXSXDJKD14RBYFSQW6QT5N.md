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
- actor: claude-code
  id: 01m4c1f77aq516q1t2ws9g571g
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD; 1 finding (1 confirmed, 1 refuted) — Sources/FoundationModelsAgents/Run/AgentRun.swift:375 (completeness/invariant-propagation). The .kanban/ files were not reviewed (.reviewignore).
    - next: implement the finding (a begin gate in deliver(_:) and a test for deliver before begin), then review again.
  timestamp: 2026-10-07T20:39:23.114840+00:00
- actor: claude-code
  id: 01m4c1fg16m86x9dw44v7mgdmt
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 6 files
    - test: green — swift test, 439 passed in 64 suites
    - commit: 224ca35
    - review: findings — Sources/FoundationModelsAgents/Run/AgentRun.swift:375
  timestamp: 2026-10-07T20:39:32.134978+00:00
- actor: claude-code
  id: 01m4c1vw4nmqv49b6ec4s6gs6n
  text: |-
    Finding AgentRun.swift:375 (completeness/invariant-propagation): the fix holds the message. It does not reject it.

    - Choice: hold the message, do not return .ended(storage.state). Reason: before begin the state is .running, thus .ended(.running) contradicts AgentRunMessageOutcome ("the final state of the run").
    - The same cause also exists AFTER begin. begin starts the driver task and returns before that task puts the task prompt in the queue (streamEvents(to:) enqueues in an inner Task). A deliver right after runner.start or harness.start sent the caller message first. The new test messageRightAfterBeginComesAfterTaskPrompt showed this: the first prompt was the caller message. Thus a flag that begin sets is not sufficient. The gate opens when the follower reads the first .submissionStarted, because that submission carries only the task prompt.
    - Implementation: Storage.callerMessages: CallerMessageGate (.holding([String]) / .open). deliver -> admit(_:in:) gives MessageAdmission (.send / .held / .ended). A held message is in inboundMessages and acceptedMessages, thus the idle rule does not end the run while it is held. follow(_:on:) calls releaseHeldMessages(to:) at each .submissionStarted. The call sends the held messages in order, then sets .open. A message that arrives while the release sends is held too, thus the order stays.
    - Known limit, documented on deliver: a run that is cancelled or fails before the start of its task answer does not send its held messages. A made run that never begins keeps its held messages.
    - Tests: messageBeforeBeginComesAfterTaskPrompt (the finding) and messageRightAfterBeginComesAfterTaskPrompt. Both failed RED (first prompt = caller message), and both pass GREEN.
    - Rules dump: the file of the dump was 754k characters (all languages). I read the completeness/invariant-propagation, swift and test-integrity sections in full, not the full file.
  timestamp: 2026-10-07T20:46:17.749257+00:00
- actor: claude-code
  id: 01m4c1vz09exnstkgk1m1p7t2f
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsAgents/Run/AgentRun.swift, Sources/FoundationModelsAgents/Run/AgentRun+Drive.swift, Tests/FoundationModelsAgentsTests/AgentRunMessageTests.swift. RED: `swift test --filter "AgentRunMessageTests/message(Before|RightAfter)Begin"` 2 tests failed (7 issues). GREEN: same filter, 2 passed. Full `swift test`: 441 tests in 64 suites passed. The one build warning ("missing creator for mutated node ... mlx-swift_Cmlx.bundle") comes from the mlx dependency. Finding AgentRun.swift:375 checked.
    - next: /review
  timestamp: 2026-10-07T20:46:20.681474+00:00
- actor: claude-code
  id: 01m4c26wv2pkphe093wpkwf1h2
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 3443136). 0 findings (7 validator runs, 0 failed). 3 source files reviewed. 2 .kanban/ files excluded. The one prior finding is checked.
    - next: none. The task moved to done.
  timestamp: 2026-10-07T20:52:18.914612+00:00
- actor: claude-code
  id: 01m4c274gahw8t2ajw2jm993qm
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 3 files
    - test: green — swift test, 441 passed in 64 suites (3 runs)
    - commit: 3443136
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-10-07T20:52:26.762949+00:00
position_column: done
position_ordinal: c480
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

## Review Findings (2026-10-07 15:35)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 16 not reviewed.

> 16 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 16 file(s)

- [x] `Sources/FoundationModelsAgents/Run/AgentRun.swift:375` `completeness/invariant-propagation` — deliver(_:) admits a message to any run that has a session, without checking that begin(_:environment:) was called. A made run that has not begun has a session, so deliver sends the caller message to the session before the task prompt. This breaks the rule that a made run sends no prompt until begin, and no test covers a message sent before begin without a cancel. Add a begin gate to the admission in deliver(_:), for example a flag set by begin that deliver checks, and return .ended(storage.state) or hold the message until begin. Add one test that calls deliver on a made run before begin and asserts the message is not sent before the task prompt.
