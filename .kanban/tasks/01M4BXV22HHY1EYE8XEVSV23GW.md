---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4byc9n6hnw67a6s8vcebeak
  text: |-
    Extras API is final (local main 2c37a78, not pushed yet):
    - `OperationEventKind.message`: the wire value is "message". It is never terminal. `detail` holds the text, and `outcome` is nil.
    - `ToolContext.message(_ text: String) async`: it posts a `.message` event. The event has the tool, the op and the completionToken of the call, the same as `progress(_:)`.
    - After the terminal event of the call, the funnel drops a `.message` and gives no error. A run that is still running always has an open `start agent` call, thus `send caller` from a running child is always delivered.
    - A `.message` resets the timeout window of the run, the same as progress.
    - FoundationModelsAgents has no exhaustive switch over `OperationEventKind` (checked with grep). Thus the update of the package needs no change for the new case.
  timestamp: 2026-10-07T19:45:21.574125+00:00
depends_on:
- 01M4BXTKA17C1EXCN9TZ152P5M
position_column: todo
position_ordinal: '8380'
title: 'send caller (alias send parent): a run sends a message to its caller as mail'
---
## What
Add the `send caller` operation. `send parent` is a noun synonym of it. A run sends a message to the session that started it, and the run continues. The calling session can be a parent run or the root host session. It gets the message as mail, and the Router starts an answer for it.

Also, `send agent` with an `id` that is the session id of the caller does the same as `send caller`. A run id is the session id, thus the parent run id works as that `id`.

External APIs (the names that the Extras and Router sessions confirmed):
- Extras: `OperationEventKind.message` and `ToolContext.message(_ text: String) async`.
- Router: `SessionEvent.runMessage(OperationEvent)`. An unheld `.message` whose token is an open or a settled background run starts an answer with no caller message (Router kanban `^v270zf4`).

First, update `Package.resolved` and `IntegrationTests/Package.resolved` to the Extras and Router `main` that have these APIs.

Files:
- `Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift`: new `@Operation(verb: "send", noun: "caller", description: "Send a message to the session that started you. You continue to work. Your final message still goes to it when you end.") struct SendCaller { var message: String }`.
  - `execute` uses `context.callerLink`. With no link, it gives `.corrective(AgentsToolText.noCaller)`: "You have no caller."
  - A blank message gives `.corrective(AgentsToolText.blankMessage)`.
  - Otherwise, it calls `await link.call.message(message)` and gives `.success(AgentsToolText.messageSentToCaller)`.
  - `SendAgent.execute`: before `answer(forRun:)`, if `id` (trimmed, not case-sensitive) is `context.callerLink?.sessionID`, it does the same as `SendCaller`.
- `Sources/FoundationModelsAgents/Tool/AgentsTool.swift`: add `SendCaller` to the full op list and to the `.messagingOnly` op list. Add `nounAliases: ["parent": "caller"]` to the `OperationResolver`.
- `Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift`: when the context has a caller link, add this sentence: "The session that started you has the id <id>. Send a message to it with {\"op\": \"send caller\", \"message\": \"...\"}."
- `Sources/FoundationModelsAgents/Tool/AgentsToolText.swift`: the texts above.

## Acceptance Criteria
- [ ] A running child that calls `send caller` causes a new answer in the parent session. The message text is in the mail of that answer. The child continues, and it ends later with its final message.
- [ ] `{"op": "send parent", ...}` resolves to `send caller`.
- [ ] `send agent` with the id of the parent run delivers to the parent session.
- [ ] A host-started run with a full tool and no caller gets the "You have no caller." corrective.
- [ ] The tool description of a run with a caller link names the caller id.

## Tests
- [ ] New `Tests/FoundationModelsAgentsTests/SendCallerTests.swift` with the scripted model:
  - the child posts a message;
  - the parent gets a `.runMessage` and answers the mail;
  - then the child finishes and the parent gets the final message.
  - Hold the child with `ScriptedGate` until the parent has answered the message mail, so that this test does not depend on the parent idle rule of the next task.
- [ ] Alias test: `send parent` resolves. Parent-id test: `send agent` with the caller id delivers.
- [ ] Update `AgentsToolSchemaTests.swift` (both op lists) and `AgentsToolDescriptionTests.swift` (the caller sentence).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass. #waits-on-router