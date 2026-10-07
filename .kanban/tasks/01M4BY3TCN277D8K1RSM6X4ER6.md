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
- actor: claude-code
  id: 01m4cbpjway44626d19xejwkbb
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (6ef23cd); 3 findings (3 confirmed, 1 refuted) — Sources/FoundationModelsAgents/Run/AgentRunner.swift:339, Sources/FoundationModelsAgents/Tools/ToolResolver.swift:17, Tests/FoundationModelsAgentsTests/ToolResolverTests.swift:392. No finding asks for a change to plan.md, DocC or README (that work is for ^125tp66), so no finding was dropped.
    - next: correct the 3 open items in the dated Review Findings section, then review again.
  timestamp: 2026-10-07T23:38:10.186377+00:00
- actor: claude-code
  id: 01m4cbpwtjvgegnyjgr74102z1
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 8 files
    - test: green — swift test, 494 passed in 68 suites; IntegrationTests build complete; live suite 13 passed
    - commit: 6ef23cd
    - review: findings — Sources/FoundationModelsAgents/Run/AgentRunner.swift:339, Sources/FoundationModelsAgents/Tools/ToolResolver.swift:17, Tests/FoundationModelsAgentsTests/ToolResolverTests.swift:392
  timestamp: 2026-10-07T23:38:20.370181+00:00
- actor: claude-code
  id: 01m4cby2q9jpqwxp5ew4n64prx
  text: |-
    Review findings (2026-10-07 18:35) corrected with TDD.

    - One text, one source: `ToolResolver.maxDepthAgentEntryMessage` now tells both cases: "each run of this agent is at maxDepth, thus its 'Agent' entry cannot start agents: a run with a caller gets only the message ops (send caller, send agent), and a host-started run gets no agents tool". `AgentRunner.catalog()` and `ToolResolver.diagnostics` doc comments state the same two cases. No second copy of the text.
    - Why both cases are real at maxDepth 1: a host session with the agents tool starts a run at depth 1 with a caller (messaging tool); `runner.start` starts a run at depth 1 with no caller (no tool).
    - Tests: `ToolResolverTests.agentEntryAtMaxDepthIsWarned` now checks both phrases (`callerRunMaxDepthPhrase` keeps "only the message ops"). New catalog test `AgentRunnerTests.catalogAtHostDepthWarnsAboutTheHostStartedRun` (fixture `lead`, maxDepth = hostDepth). New `AgentsToolMountTests.hostStartedRunAtMaxDepthGetsNoTool` proves the host-started claim of the text (the run finishes, and its play has no tool).
    - RED: the two message tests failed on the old text (8 issues). GREEN after the text change.
    - Empty-collection check: `incorrectToolKeyResolvesToLessAccess` now asserts `calls.grants == [nil]` (each of the 4 cases calls the factory one time, because a broken `disallowedTools` gives `tools: []`, not a deny). Other new assertions of this task: `calls.grants.isEmpty` in the deny tests is paired with an exact `tools` list; `child.tools.isEmpty` / `record.tools.isEmpty` are paired with `toolNames(ofPlay:) == []`, which is `nil` (so false) when the play did not run; `child.tools.map(...) == [.messagingOnly]` is exact. No other empty-collection weakness.
  timestamp: 2026-10-07T23:42:15.785844+00:00
- actor: claude-code
  id: 01m4cby4zj61d9pf1kc4fqse35
  text: |-
    ### implement — changed
    - evidence: `swift test` — 496 tests in 68 suites passed, 0 failures, no compiler warning (only the known SwiftPM mlx-swift bundle line). Files: Sources/FoundationModelsAgents/Tools/ToolResolver.swift, Sources/FoundationModelsAgents/Run/AgentRunner.swift, Tests/FoundationModelsAgentsTests/ToolResolverTests.swift, Tests/FoundationModelsAgentsTests/AgentRunnerTests.swift, Tests/FoundationModelsAgentsTests/AgentsToolMountTests.swift. 3 of 3 findings checked.
    - next: /review
  timestamp: 2026-10-07T23:42:18.098418+00:00
- actor: claude-code
  id: 01m4cc2mp3qb6apgphyxwqye8g
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (51c7da0): 0 findings (5 files reviewed, 2 .kanban/ files excluded). All 3 prior Review Findings items are checked.
    - next: task moved to done.
  timestamp: 2026-10-07T23:44:45.251227+00:00
- actor: claude-code
  id: 01m4cc2tapepvqgetj1sx74d80
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 5 files
    - test: green — swift test, 496 passed in 68 suites; IntegrationTests build complete
    - commit: 51c7da0
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-10-07T23:44:51.030345+00:00
depends_on:
- 01M4BXV22HHY1EYE8XEVSV23GW
position_column: done
position_ordinal: ca80
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

## Review Findings (2026-10-07 18:35)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsAgents/Run/AgentRunner.swift:339` `completeness/public-output-contract` — The catalog warning for an Agent entry says the run gives only the message ops. This is true only for a run with a caller. Here atMaxDepth is true when maxDepth equals hostDepth, which is the host-started case. A host-started run at maxDepth has no caller, so AgentSessionMaker gives it no messaging tool. The warning then names a tool the run never gets. Make the warning text match both cases, or word it for a run with a caller only. For example: 'at maxDepth, a run with a caller gets only the message ops; a host-started run gets no agents tool.' Add a catalog test for the host-started case.
- [x] `Sources/FoundationModelsAgents/Tools/ToolResolver.swift:17` `completeness/public-output-contract` — The maxDepth warning text is the only text that tells the author the Agent entry gives only the message ops. It does not say what happens for a host-started run at maxDepth, where the entry gives nothing. The text is therefore incomplete for one of the two cases the diff creates. Extend the message to cover both cases, and check that the existing test at ToolResolverTests 'at maxDepth, an Agent entry gives a warning' still matches the text it asserts ('only the message ops').
- [x] `Tests/FoundationModelsAgentsTests/ToolResolverTests.swift:392` `test-integrity/no-test-cheating` — The assertion `await calls.grants.allSatisfy { $0 == nil }` is true for an empty array. If the resolver stopped calling the agents tool factory, this test would still pass, so it cannot prove that the factory got a nil grant. It is a weakened assertion. It should check the exact recorded value, as the other tests in this change do. Replace the assertion with `#expect(await calls.grants == [nil])`, or add `#expect(await calls.grants.count == 1)` before the `allSatisfy` check.
