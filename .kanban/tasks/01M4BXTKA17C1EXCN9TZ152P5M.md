---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4c2yzt09ncjmn0wa8whtp81
  text: |-
    Research done.
    - `ToolResolver.AgentsToolFactory` keeps its signature `([String]?) -> any Tool`. The closure in `AgentSessionMaker.agentsToolFactory` captures the link and the grant, thus `ToolResolverTests` (:104, :121) need no change.
    - `AgentRunRequest.AgentsToolMaker` gets `(ParentRun, CallerLink?, Grant, [String]?)`. Callers: `AgentRun.agentsTool(of:)`, `AgentSessionMaker.agentsToolFactory`, and the test `AgentSchedulingTests+Setup.leadRequest` (it wraps the maker; it must change too).
    - `AgentsToolContext.init(runner:allowedNames:parent:)` gets `callerLink:` and `grant:`. Test caller: `NestedRunTests+Limits` (atLimit tool).
    - Test seam for the child link: `AgentStartProbe` gives the real `ToolContext` of a call in a Router session; a wrapping maker records the made `AgentsTool`. The real `start agent` path hard-wires `AgentRun.agentsTool(of:)`, thus a test cannot see the tool of a child that `start agent` started.
    - `AgentsToolSchema.make` works with no `name` field (the `name` enum applies only to a `name` parameter).
  timestamp: 2026-10-07T21:05:28.384015+00:00
- actor: claude-code
  id: 01m4c3cew6awc6m6t09j15r6sz
  text: |-
    ### implement — changed
    - evidence: `swift test` — 454 tests in 65 suites passed, 0 failed. `swift build --package-path IntegrationTests --build-tests` — build complete. RED seen first: the build of the new tests failed with "'Grant' is not a member type of struct 'AgentsToolContext'".
    - files (sources): Tool/AgentsToolContext.swift (CallerLink, Grant, callerLink, grant, init), Tool/AgentsTool.swift (make selects the op list from the grant; private make(context:description:agentNames:) and operations(of:)), Tool/AgentsToolDescription.swift (`messaging` text; shared `opSentence`), Run/AgentRunRequest.swift (AgentsToolMaker takes CallerLink? and Grant), Run/AgentRun.swift (agentsTool(of:)), Run/AgentSessionMaker.swift (link from request.context, grant `.full`).
    - files (tests): AgentsToolMountTests (3 caller-link tests and a MadeToolRecord maker wrapper), AgentsToolSchemaTests (3 `.messagingOnly` tests), Support/AgentsToolHarness (`grant:`), and the call sites that the new maker and init signatures change: AgentSchedulingTests+Setup, NestedRunTests+Limits, AgentRunLoggingTests, AgentRunMetricsTests, AgentRunTracingTests, AgentRunTests+Failures.
    - notes: `ToolResolver.AgentsToolFactory` did not change, thus `ToolResolverTests` and `AgentRunHarness` needed no edit. The mount rule did not change: `AgentSessionMaker` always gives `.full`. The `.messagingOnly` op list has only `send agent`; `send caller` comes in ^vsv23gw. The build prints "missing creator for mutated node ... mlx-swift_Cmlx.bundle"; this comes from the SwiftPM build graph of mlx-swift, not from this change. swiftlint reports `file_length` on Run/AgentRun.swift (607 lines); the file was 605 lines before this change.
    - next: /review
  timestamp: 2026-10-07T21:12:49.798651+00:00
depends_on:
- 01M4BXT7ZTAKCNYM4N04Z6VJEP
position_column: doing
position_ordinal: '80'
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
- [x] The tool of a child run with an `Agent` grant has a `callerLink` whose `sessionID` is the parent session id, and whose `call.completionToken` is the token of the `start agent` call.
- [x] The tool of a host session or of a host-started run has `callerLink == nil`.
- [x] `AgentsTool.make` with `.messagingOnly` gives a tool whose schema has no `list`, `start`, `check` or `cancel` op, and whose description names no agent.
- [x] The mount rule is not changed: each existing mount test passes.

## Tests
- [x] Add tests to `Tests/FoundationModelsAgentsTests/AgentsToolMountTests.swift` for the caller link.
- [x] Add a schema test for `.messagingOnly` in `AgentsToolSchemaTests.swift`.
- [x] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.