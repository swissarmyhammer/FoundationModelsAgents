---
assignees:
- claude-code
depends_on:
- 01M4BXSXDJKD14RBYFSQW6QT5N
position_column: todo
position_ordinal: '8180'
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
- [ ] `{"op": "send agent", "id": <run id>, "message": "..."}` to a running child is a success, and the child session gets the message and answers it.
- [ ] The completion token from the pending envelope works as the id.
- [ ] An ended run gives the `runEnded` corrective with its state. An id of a different caller gives the unknown-run corrective.
- [ ] A blank message gives a corrective.
- [ ] The tool schema `op` enum has `send agent`, and the schema has the `message` field.

## Tests
- [ ] New `Tests/FoundationModelsAgentsTests/SendAgentTests.swift` with `AgentsToolHarness`:
  - delivered;
  - by token;
  - ended (finished / cancelled / failed);
  - different caller;
  - blank message.
- [ ] Update `AgentsToolSchemaTests.swift` (op list, field map, property set).
- [ ] The existing `check agent` and `cancel agent` tests pass unchanged.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.