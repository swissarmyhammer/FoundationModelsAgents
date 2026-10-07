---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4cb3f5s87rm4nc6q17ajcxa
  text: |-
    Research:
    - `ToolResolver.AgentsToolFactory` takes only the allowed names. The resolver mounts the tool only when `selection.agentsGrant != nil`. `ToolSelection` sets `agentsGrant = nil` both for "no Agent entry" and for "disallowedTools denies it". Thus the resolver cannot tell the two cases. Plan: `ToolSelection` keeps `deniesAgents`, and the factory gets the grant (`AgentsGrant?`, `nil` for no entry) and gives `(any Tool)?`.
    - `AgentSessionMaker.agentsToolFactory` decides the table: host-started run (`context == nil`): a grant below `maxDepth` gives `.full`, no grant or `maxDepth` gives no tool (as now). Run with a caller: a grant below `maxDepth` gives `.full`; each other case gives `.messagingOnly`.
    - There is no maxDepth diagnostic now. `runner.catalog()` reads each definition, not a run, thus it knows no depth. The only static case is `maxDepth == AgentRunner.hostDepth` (1): then each run is at `maxDepth`, and an `Agent` entry gives only the message ops. The diagnostic is for that case.
    - Fixture agents: `lead` (`tools: Agent(code-reviewer, test-writer)`), `code-reviewer` (`tools: Read, Grep`), `test-writer` (no `tools` key). The deny row needs a temporary layer.
    - Expected effect on other tests: each child run that a test starts through `start agent` gets the messaging tool now. Tests that pin `toolNames(ofPlay:) == []` for a child change.
  timestamp: 2026-10-07T23:27:43.801370+00:00
- actor: claude-code
  id: 01m4cbbxp0v6w08fkrjz6mep6y
  text: |-
    Implementation landed (TDD: the new tests did not compile first, because the API was missing; then green).

    Design:
    - `ToolResolver.AgentsToolFactory` is now `@Sendable (AgentsGrant?) async throws -> (any Tool)?`. The resolver gives the joined grant of the `Agent` entries, or `nil` when no entry grants the tool. The factory gives `nil` when the run gets no tool.
    - `ToolSelection.deniesAgents`: a `disallowedTools` `Agent`/`agents` entry denies each grant. The resolver then does not call the factory (explicit deny wins).
    - `AgentSessionMaker.mountedGrant(for:belowMaxDepth:hasCaller:)` holds the mount table: an `Agent` entry below `maxDepth` gives `.full`; each other case with a caller gives `.messagingOnly`; else no tool. A host-started run at `maxDepth` gets no factory (as before).
    - `ToolResolver.diagnostics(of:catalog:hasAgentsTool:atMaxDepth:)`: with `atMaxDepth` and a grant that is not denied, one warning that says "only the message ops". `AgentRunner` passes `atMaxDepth: environment.maxDepth <= AgentRunner.hostDepth`, because the catalog reads definitions, not runs: only with `maxDepth == 1` is each run at `maxDepth`.

    Tests that pinned the old mount and changed: `NestedRunTests+Limits` (`childAtMaxDepthHasTheMessagingTool`, `noToolsKeyGivesTheMessagingTool`): the child now has the `agents` tool (messaging). `ToolResolverTests` factory helper records the grant.

    Doc comments of `ToolSelection`, `ToolResolver`, `AgentSessionMaker`, `AgentRunner.catalog()` and `StartAgent.execute` now state the new rule. plan.md, DocC and README stay for ^125tp66.

    Note: `swift test` prints one SwiftPM build-system line, `warning: missing creator for mutated node: ...mlx-swift_Cmlx.bundle/Contents/MacOS`. It comes from the mlx-swift dependency bundle, not from a source file of this package. There is no compiler warning.
  timestamp: 2026-10-07T23:32:20.800542+00:00
- actor: claude-code
  id: 01m4cbcdtjbahs9e51031ha7f9
  text: |-
    ### implement — changed
    - evidence: `swift test` — 494 tests in 68 suites passed, 0 failures, no compiler warning. Files: Sources/FoundationModelsAgents/Run/AgentSessionMaker.swift, Sources/FoundationModelsAgents/Run/AgentRunner.swift, Sources/FoundationModelsAgents/Tools/ToolResolver.swift, Sources/FoundationModelsAgents/Tools/ToolSelection.swift, Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift (doc comment), Tests/FoundationModelsAgentsTests/AgentsToolMountTests.swift, Tests/FoundationModelsAgentsTests/ToolResolverTests.swift, Tests/FoundationModelsAgentsTests/NestedRunTests+Limits.swift.
    - Row tests: Agent entry below maxDepth `childToolKnowsItsCaller` (.full); at maxDepth `agentEntryAtMaxDepthGivesTheMessagingTool`; tools key with no Agent entry `toolsKeyWithNoAgentEntryGivesTheMessagingTool`; no tools key `noToolsKeyGivesTheMessagingTool`; deny `disallowedAgentsToolGivesNoTool` (Agent, agents); host-started with no grant `hostStartedRunWithNoGrantGetsNoTool`. Messaging description: existing `AgentsToolSchemaTests.theMessagingDescriptionNamesNoAgentAndNoStart`.
    - next: /review
  timestamp: 2026-10-07T23:32:37.330669+00:00
depends_on:
- 01M4BXV22HHY1EYE8XEVSV23GW
position_column: doing
position_ordinal: '80'
title: Each run with a caller gets the messaging tool
---
## What
Change the mount rule so that each run with a caller can send a message to it.

The rule (it applies to a run with `request.context != nil`):

| Case | Tool |
|---|---|
| `Agent`, `Agent(a, b)` or `agents` entry, below `maxDepth` | the full tool (as now) |
| the same entry, at `maxDepth` | the messaging tool (`send caller`, `send agent`) |
| a `tools` key with no such entry | the messaging tool |
| no `tools` key | the messaging tool |
| `disallowedTools` has `agents` or `Agent` | no tool (an explicit deny wins) |

A host-started run (`context == nil`) with no grant gets no tool, as now.

Files:
- `Sources/FoundationModelsAgents/Run/AgentSessionMaker.swift` (`agentsToolFactory` at :130): this is the place that decides the mount, because only it knows `request.context`. Give `.messagingOnly` for the cases above.
- `Sources/FoundationModelsAgents/Tools/ToolResolver.swift` (:64-75): mount the tool that the factory gives when there is no `agentsGrant`, unless `disallowedTools` denies it.
- `Sources/FoundationModelsAgents/Tools/ToolResolver.swift` `diagnostics(... hasAgentsTool:)` and `Sources/FoundationModelsAgents/Run/AgentRunner.swift` :335: at `maxDepth`, the warning says that the `Agent` entry gives only the message ops.

## Acceptance Criteria
- [x] Each row of the table above has a passing test.
- [x] The messaging tool description names no agents and no `start agent`.
- [x] The maxDepth warning text says "only the message ops".

## Tests
- [x] Update `Tests/FoundationModelsAgentsTests/AgentsToolMountTests.swift`: one test for each row.
- [x] Update `Tests/FoundationModelsAgentsTests/NestedRunTests+Limits.swift`: at `maxDepth`, expect the messaging tool.
- [x] Update `Tests/FoundationModelsAgentsTests/ToolResolverTests.swift`: the `disallowedTools` deny, and the maxDepth diagnostic.
- [x] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.