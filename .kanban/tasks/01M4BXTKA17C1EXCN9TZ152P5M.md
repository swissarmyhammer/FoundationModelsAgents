---
assignees:
- claude-code
depends_on:
- 01M4BXT7ZTAKCNYM4N04Z6VJEP
position_column: todo
position_ordinal: '8280'
title: The agents tool knows the caller of its run (CallerLink and grant plumbing)
---
## What
The `agents` tool of a run must know the link to the caller of that run, so that `send caller` can use it. This task does not change which runs get the tool. The mount rule is changed in the task "Each run with a caller gets the messaging tool".

The link has two parts:
- the `ToolContext` of the `start agent` call in the calling session (`AgentRun.context`);
- the session id of the caller (`AgentRun.caller`).

Files:
- `Sources/FoundationModelsAgents/Tool/AgentsToolContext.swift`:
  - Add `struct CallerLink: Sendable { let call: ToolContext; let sessionID: ULID }`.
  - Add `let callerLink: CallerLink?`.
  - Add `let grant: Grant` (`.full` / `.messagingOnly`). Only `.full` is made in this task.
- `Sources/FoundationModelsAgents/Tool/AgentsTool.swift`: `make` selects the op list from `grant`. For `.messagingOnly`:
  - the op list has only the message ops;
  - `make` does not need the catalog;
  - the description is short and has no agent list.
- `Sources/FoundationModelsAgents/Run/AgentRun.swift` (`agentsTool(of:)` at :200) and `Run/AgentRunRequest.swift` (`AgentsToolMaker`): pass `CallerLink?` and `Grant`.
- `Sources/FoundationModelsAgents/Run/AgentSessionMaker.swift` (`agentsToolFactory` at :130): make the link from `request.context`.
- Tests that use the changed signatures: `Tests/FoundationModelsAgentsTests/Support/AgentRunHarness.swift` (:195, :228) and `Tests/FoundationModelsAgentsTests/ToolResolverTests.swift` (:104, :121).

## Acceptance Criteria
- [ ] The tool of a child run with an `Agent` grant has a `callerLink` whose `sessionID` is the parent session id, and whose `call.completionToken` is the token of the `start agent` call.
- [ ] The tool of a host session or of a host-started run has `callerLink == nil`.
- [ ] `AgentsTool.make` with `.messagingOnly` gives a tool whose schema has no `list`, `start`, `check` or `cancel` op, and whose description names no agent.
- [ ] The mount rule is not changed: each existing mount test passes.

## Tests
- [ ] Add tests to `Tests/FoundationModelsAgentsTests/AgentsToolMountTests.swift` for the caller link.
- [ ] Add a schema test for `.messagingOnly` in `AgentsToolSchemaTests.swift`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.