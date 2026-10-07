---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4c29wb05dtv7v50201aktgm
  text: |-
    Research:
    - `AgentsToolContext.answer(forRun:_:)` finds the run by id or by completion token, waits for an open start body, and gives the unknown-run corrective for a different caller. Its body is sync now; change it to async.
    - `AgentRun.deliver(_:)` gives `.delivered` or `.ended(AgentRunState)`. A message before the task answer starts is held, thus a send right after start is safe.
    - Test plan: outside a Router session (`harness.call`) for delivered, ended, blank. Root sessions on the `standard` slot for the token test and the different-caller test. The token test uses a `.wait` gate in the root play, then a `.deferredToolCall` whose arguments the test sets from the token in `script.toolOutputs`.
    - The "four operations" doc comments are in the scope of ^125tp66 (Documents task). This task does not change them.
  timestamp: 2026-10-07T20:53:56.704851+00:00
- actor: claude-code
  id: 01m4c2jy0yek8wk3xmhpeavph9
  text: |-
    Implementation landed (TDD):
    - RED: `swift build --build-tests` failed only on the missing `AgentsToolText.blankMessage` in the new SendAgentTests.
    - GREEN: `swift test --filter "SendAgentTests|AgentsToolSchemaTests"` gave 14 tests, all passed.
    - `SendAgent` checks for a blank message first, then uses `context.answer(forRun:)` with an async body that calls `run.deliver(message)`.
    - `runEnded` names the state with one word (running, finished, failed, cancelled), through a private exhaustive switch. It uses `run.id`, also when the model gave the completion token.
    - The token test holds the root play on a `.wait` gate after `start agent`, reads the token from `script.toolOutputs.first`, and sets a `.deferredToolCall` for `send agent`. No change to test support was necessary.
    - Doc comments that list the synchronous operations now name `send agent`. The "four operations" doc comments stay for ^125tp66.
    - The full `swift test` gives one `warning:` line from the build system for the mlx-swift_Cmlx bundle ("missing creator for mutated node"). It is not from project code.
  timestamp: 2026-10-07T20:58:53.342863+00:00
- actor: claude-code
  id: 01m4c2k0gfz369cvz1ypyqwjdj
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift, Tool/AgentsToolContext.swift, Tool/AgentsTool.swift, Tool/AgentsToolText.swift, Tests/FoundationModelsAgentsTests/SendAgentTests.swift (new, 7 tests), Tests/FoundationModelsAgentsTests/AgentsToolSchemaTests.swift; `swift test`: 448 tests in 65 suites passed, 0 failures
    - next: /review
  timestamp: 2026-10-07T20:58:55.887219+00:00
depends_on:
- 01M4BXSXDJKD14RBYFSQW6QT5N
position_column: doing
position_ordinal: '80'
title: 'send agent: a caller sends a message to a run that it started'
---
## What
Add the `send agent` operation to the `agents` tool. The caller sends a message to a run that it started. If that run ended, the caller gets a corrective.

Files:
- `Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift`: new `@Generable @Operation(verb: "send", noun: "agent", description: "Send a message to a run that you started. The run answers it before it ends.") struct SendAgent { var id: String; var message: String }`.
- `Sources/FoundationModelsAgents/Tool/AgentsToolContext.swift`: change the body of `answer(forRun:_:)` to `(AgentRun) async -> AgentsToolAnswer`. Add `await` in `CheckAgent` and `CancelAgent`.
- `Sources/FoundationModelsAgents/Tool/AgentsTool.swift`: add `AnyOperation(SendAgent.self)` to `operations`.
- `Sources/FoundationModelsAgents/Tool/AgentsToolText.swift`: `runEnded(id:state:)`, `messageSent(to:)`, `blankMessage`.
- `Tests/FoundationModelsAgentsTests/AgentsToolSchemaTests.swift`: the op list at :19, the field map at :59-62, and the property set at :72 (add `message`).

Approach:
- `execute(in:)` uses `context.answer(forRun: id)`. Thus it finds a run by its id or by the completion token of its `start agent` call, it waits for an open start body, and it gives the unknown-run corrective for a run of a different caller.
- In the body, it calls `await run.deliver(message)`:
  - `.delivered` → `.success(AgentsToolText.messageSent(to: run))`: "The message was sent to <run.subject>. Its final message comes to you as mail."
  - `.ended(state)` → `.corrective(AgentsToolText.runEnded(id:state:))`: "The run <id> ended (<state>), and it gets no more messages. Start a new run."
- A blank `message` gives `.corrective(AgentsToolText.blankMessage)`.

## Acceptance Criteria
- [x] `{"op": "send agent", "id": <run id>, "message": "..."}` to a running child is a success, and the child session gets the message and answers it.
- [x] The completion token from the pending envelope works as the id.
- [x] An ended run gives the `runEnded` corrective with its state. An id of a different caller gives the unknown-run corrective.
- [x] A blank message gives a corrective.
- [x] The tool schema `op` enum has `send agent`, and the schema has the `message` field.

## Tests
- [x] New `Tests/FoundationModelsAgentsTests/SendAgentTests.swift` with `AgentsToolHarness`:
  - delivered;
  - by token;
  - ended (finished / cancelled / failed);
  - different caller;
  - blank message.
- [x] Update `AgentsToolSchemaTests.swift` (op list, field map, property set).
- [x] The existing `check agent` and `cancel agent` tests pass unchanged.
- [x] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.