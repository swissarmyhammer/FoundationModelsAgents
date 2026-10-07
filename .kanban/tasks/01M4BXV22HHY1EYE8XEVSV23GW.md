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
- actor: claude-code
  id: 01m4c2b32ydp6tgnj86t7hm05m
  text: |-
    Router API is final (Router local main 5713abe, ^v270zf4; it is not pushed yet):
    - `SessionEvent.runMessage(OperationEvent)`.
    - The mail render is `[<tool>] <op> (<token>) message, still running: <detail>`.
    - When only run messages start an answer, the prompt is "Background work you started sent you a message, and it is above. The work is still running, and its result comes later. Act on the message, or say what you did with it." When the mail holds the terminal of a settled run, the settled-run prompt is used.
    - Router aad6ae5 removes `RoutedEmbedder.dimension`. FoundationModelsAgents does not use `RoutedEmbedder`, `PooledEmbedding` or `.dimension` (checked with grep), so this change needs no work here.
    - Update `Package.resolved` and `IntegrationTests/Package.resolved` only after the Router change is pushed to origin.
  timestamp: 2026-10-07T20:54:36.382772+00:00
- actor: claude-code
  id: 01m4c2s0kewamhn4m646kbf84j
  text: 'The Router is on origin/main at 5713abe (aad6ae5 is before it). Extras is on origin/main at 2c37a78. The first step of this task: run `swift package update FoundationModelsRouter FoundationModelsExtras` in the root package and in `IntegrationTests/`. Then build, and confirm that Package.resolved names these SHAs.'
  timestamp: 2026-10-07T21:02:12.590751+00:00
- actor: claude-code
  id: 01m4c6458qmm073hqkwmtmm1c6
  text: |-
    Picked up. Package update done: root and IntegrationTests Package.resolved name Router 5713abe and Extras 2c37a78 (Package.resolved is in .gitignore, so git shows no diff for it).

    Breaking change from the update: `SessionEvent` has four new cases (`compactionStarted`, `compactionFailed`, `reasoningStopped`, `runMessage`). The exhaustive switch in `Examples/agents-demo/DemoModes.swift` `lines(for:)` did not compile. Fix: these four cases give no line. The demo line for `runMessage` is for the CLI task ^m579cf if a line is necessary.

    Research:
    - Tests can not make a `ToolContext` easily (it needs a RunPlane and a sink). A test gets a real one from `AgentStartProbe` (as AgentsToolMountTests does).
    - The scripted model: the `lead` fixture agent has an Agent grant, so a `lead` run that a root session starts has a full tool with a caller link. `.finalTextOfLastPrompt` on the root answers mail with the mail text.
    - Plan: `AgentsToolContext.messageCaller(_:)` and `isCaller(id:)` shared by `SendCaller` and `SendAgent`; `AgentsToolDescription.addingCaller(to:callerID:)` used in both grant branches of `AgentsTool.make`.
  timestamp: 2026-10-07T22:00:43.543147+00:00
- actor: claude-code
  id: 01m4c6pg4qgq1m39cm2efeths3
  text: |-
    Implementation landed.

    - `SendCaller` and the `parent` → `caller` noun alias. `AgentsToolContext.messageCaller(_:)` holds the send logic (no link → "You have no caller.", blank → blankMessage, else `callerLink.call.message`). `SendAgent` calls it when `isCaller(id)` is true (trimmed, case does not matter, compared as ULID). The repeated id normalization in the context is now one `key(of:)` helper.
    - The caller sentence is added in the shared private `AgentsTool.make`, thus both grants get it.

    What did not work first: in `SendCallerTests` the root session and the `lead` run both used the `standard` slot. The child waits on the gate inside its generation call, and it holds the one generation queue of that slot. The root mail answer then waited behind it, and the test hung until the time limit. Fix: the root session is on the `flash` slot. A later test that holds a child on a gate and expects the caller to answer must put the two on different slots.

    Correction of my first comment: the CLI task is ^x3579cf, not ^m579cf. The demo gives no line for `runMessage` now; a line for it belongs to ^x3579cf if one is necessary.

    The build has one build-system warning, "missing creator for mutated node ... mlx-swift_Cmlx.bundle", that was there before any change of this task.

    ### implement — changed
    - evidence: 9 files — Examples/agents-demo/DemoModes.swift, Sources/FoundationModelsAgents/Tool/{AgentsTool,AgentsToolContext,AgentsToolDescription,AgentsToolOperations,AgentsToolText}.swift, Tests/FoundationModelsAgentsTests/{SendCallerTests (new),AgentsToolSchemaTests,AgentsToolDescriptionTests}.swift. `swift test`: 462 tests in 66 suites passed. `swift build --build-tests --package-path IntegrationTests`: complete.
    - next: /review
  timestamp: 2026-10-07T22:10:44.503402+00:00
depends_on:
- 01M4BXTKA17C1EXCN9TZ152P5M
position_column: doing
position_ordinal: '80'
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
- [x] A running child that calls `send caller` causes a new answer in the parent session. The message text is in the mail of that answer. The child continues, and it ends later with its final message.
- [x] `{"op": "send parent", ...}` resolves to `send caller`.
- [x] `send agent` with the id of the parent run delivers to the parent session.
- [x] A host-started run with a full tool and no caller gets the "You have no caller." corrective.
- [x] The tool description of a run with a caller link names the caller id.

## Tests
- [x] New `Tests/FoundationModelsAgentsTests/SendCallerTests.swift` with the scripted model:
  - the child posts a message;
  - the parent gets a `.runMessage` and answers the mail;
  - then the child finishes and the parent gets the final message.
  - Hold the child with `ScriptedGate` until the parent has answered the message mail, so that this test does not depend on the parent idle rule of the next task.
- [x] Alias test: `send parent` resolves. Parent-id test: `send agent` with the caller id delivers.
- [x] Update `AgentsToolSchemaTests.swift` (both op lists) and `AgentsToolDescriptionTests.swift` (the caller sentence).
- [x] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.