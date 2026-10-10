---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4javcjsp3jyp4jk8dz8r3tm
  text: '2026-10-10: User decision: use the same models as the FoundationModelsACPAgent defaults (`../FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Configuration/AgentConfiguration.swift:135-142`): standard = `mlx-community/Qwen3.8-27B-mxfp4`, flash = `mlx-community/Qwen3-4B-4bit`, embedding = `mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ`. Change `IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveProfile.swift:55-60` to these. Measure the pass counts with this profile (before and after the description change).'
  timestamp: 2026-10-10T07:18:45.593285+00:00
- actor: claude-code
  id: 01m4jbpe93vtydbevnkgbpekfx
  text: |-
    Research (implement step):
    - Profile changed in `IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveProfile.swift` to the ACPAgent defaults: standard = mlx-community/Qwen3.8-27B-mxfp4, flash = mlx-community/Qwen3-4B-4bit, embedding = mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ. The models were already in the local Hugging Face cache (host has 512 GB).
    - Router main dc642256 breaks the build: `SessionEvent.toolInvocation` now has two associated values (`AgentRunProgress.swift`, `AgentRun+TurnLimit.swift`, two test files). For this task, the local Package.resolved files pin Router to the earlier main revision 16abef2d (no path dependency, no package edit). New task ^8enkvc8 records the migration. CI resolves main fresh, thus CI fails until ^8enkvc8 lands.
    - Slots in the live tests: the root session and `lead` / `message-lead` / `word-finder` use standard (27B). `leaf` and `messenger` use flash (4B).
    - First trial run (current description, new profile): FullCircle 2/2 pass; LiveNested message test pass; LiveNested agentSpawn test FAIL at LiveNestedTests.swift:110 (`!leadStartAnswers.isEmpty`) and :114 (`readsPost`). The lead transcript shows that the lead model DID call the agents tool with {"op": "start agent", "name": "leaf", ...}. The leaf (flash) finished in 2.7 s, inside the inline settle grace of the session (`ToolMount.defaultInlineSettleGrace` = 6 s). Thus the tool answer of the start call was the final message ("Agent leaf (...) finished.\n\nPAPAYA"), not the pending envelope that holds the completion token, and no mail prompt came. The test expects the pending envelope and the mail. This failure is a timing race of the test, not a choice of the model. The tool description cannot change it.
  timestamp: 2026-10-10T07:33:32.067733+00:00
- actor: claude-code
  id: 01m4jdyq0k56a2d1fpvph4hx1t
  text: |-
    BEFORE (new profile, current description), N = 10 processes, each runs both suites (`swift test --package-path IntegrationTests --skip-build --filter "LiveNestedTests|FullCircleTests"`), about 3.5 min each:
    - FullCircle "start agent, a tool of the sub-agent, ..." (exact JSON): 10/10.
    - FullCircle "The root starts the sub-agent from the tool description, ...": 9/10. The one failure (run 5) is FullCircleTests.swift:100 `rejected.isEmpty`: the Router rejected the first tool call of the root as `malformed_syntax` ("The tool-call payload could not be parsed"). The 27B model wrote the correct call on the retry, and the rest of the circle passed. The transcript does not record the bad payload.
    - LiveNested "agentSpawn links three sessions, ...": 0/10. Each failure is LiveNestedTests.swift:110 (`!leadStartAnswers.isEmpty`) and :114 (`readsPost`). In each run the lead called start agent for leaf (the asserts at :106-:108 passed), and leaf (flash, 4B) finished inside the 6 s inline settle grace. Thus the start call gave the final message inline, and no pending envelope and no mail came. The description cannot fix this.
    - LiveNested "a child sends one progress message ...": 10/10.
  timestamp: 2026-10-10T08:13:00.307134+00:00
- actor: claude-code
  id: 01m4jg9vrbv409a0gnvnb47cgs
  text: |-
    AFTER v1 (stopped after 5 of 10 runs). Text v1 added: "Each agent in the list below has a name and a description of the tasks that it does. Before you do a task, compare the task with the description of each agent. When the description of an agent matches the task, give the task to that agent. Do not do that task yourself. When the list does not show all the agents or their descriptions, or when no agent in the list matches the task, call the tool "agents" with the arguments {"op": "list agents"}." and "put the full task and all that the agent needs in the prompt".
    Results (5 runs): FullCircle exact JSON 5/5, FullCircle tool description 5/5, LiveNested agentSpawn 0/5 (same inline settle race), LiveNested message 3/5 (REGRESSION, :140 `!posted.isEmpty`).
    Cause of the regression (transcript of run 1): `messenger` (flash, `tools: Agent`, thus the full agents tool, whose list holds `messenger` itself) read "Do not do that task yourself", and started a NEW `messenger` run with {"op": "start agent", "name": "messenger", ...} in place of its own `send caller` call. The nested run sent the message to the first messenger, not to message-lead.
    Fix (v2): "give the task to that agent in place of doing the task yourself. But when your instructions give you the steps or the calls of the task, do them yourself." Measuring v2 with N = 10.
  timestamp: 2026-10-10T08:54:02.763467+00:00
- actor: claude-code
  id: 01m4jjvjjrd4tfebv5px8jrc43
  text: 'AFTER v2, N = 10: FullCircle exact JSON 10/10; FullCircle tool description 10/10 (before: 9/10); LiveNested agentSpawn 1/10 (the one pass is a run where leaf took more than the 6 s grace; the 9 failures are the same inline settle race at :110/:114); LiveNested message 7/10 (before: 10/10). The 3 message failures (process folders 01M4JGGM42…, 01M4JGPKJF…, 01M4JHEQJ2…) are again self-delegation: the flash `messenger` called {"op": "start agent", "name": "messenger", ...} and the nested messenger sent the message to the first messenger. Next: v3 states that the model can be one of the listed agents, and must not start an agent for the steps or calls of its own instructions.'
  timestamp: 2026-10-10T09:38:40.344787+00:00
- actor: claude-code
  id: 01m4jn6wjt34j6r151axz2r0fy
  text: |-
    AFTER v3 (current text in the tree), N = 10: FullCircle exact JSON 10/10; FullCircle tool description 9/10 (run 7, :108: the root reply to the settle mail was "The word-finder agent is still running in the background; I'll answer with its word once its final message arrives." The mail prompt held the pending envelope and the final message together); LiveNested agentSpawn 0/10 (inline settle race, :110/:114); LiveNested message 8/10 (2 runs: flash `messenger` again called {"op": "start agent", "name": "messenger", "prompt": "Do your part now."}).

    Summary, pass counts (N = 10, each process runs both suites):
    | test | before | v1 (N=5) | v2 | v3 |
    | FullCircle exact JSON | 10 | 5/5 | 10 | 10 |
    | FullCircle tool description | 9 | 5/5 | 10 | 9 |
    | LiveNested agentSpawn | 0 | 0/5 | 1 | 0 |
    | LiveNested message | 10 | 3/5 | 7 | 8 |

    Blockers (the description cannot fix them):
    1. LiveNested agentSpawn: the lead calls start agent in every run. `leaf` (flash) ends in about 3 s, inside the 6 s `ToolMount.defaultInlineSettleGrace`, thus the start call gives the final message inline, and the asserts at :110 and :114 (pending envelope with the token, mail read before the final answer) cannot hold. Proposal: give the live runner and root session `inlineSettleGrace: 0` for this test (`AgentEnvironment.make(inlineSettleGrace:)` and `SessionConfiguration.inlineSettleGrace`), so that the test examines the background path that it documents. This changes no assert.
    2. LiveNested message: the card requires "give a matching task to the matching agent". The list of the tool of a run holds the agent of that run, and the flash 4B `messenger` matches its own description, so it starts a new `messenger` run in 2 to 3 of 10 runs. Three text versions did not remove it. Proposal A (code): leave the agent of a run out of the list and the `name` enum of its own agents tool (no self-start). Proposal B (test): `messenger` needs only `send caller`; with no `Agent` entry it gets the messaging-only tool. Proposal C: revert the match sentences (before: 10/10 for this test).

    ### implement — stuck
    - evidence: 5 files — IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveProfile.swift, README.md, Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md, Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift, Tests/FoundationModelsAgentsTests/AgentsToolDescriptionTests.swift. `swift test`: 493 tests in 66 suites passed. `swift build --package-path IntegrationTests --build-tests`: exit 0. Live counts above. Local Package.resolved pins Router to main 16abef2d because Router main dc642256 does not compile with this package (^8enkvc8).
    - next: a person picks the fixes for blockers 1 and 2 (and the text to keep); the acceptance "N of N" is not met.
  timestamp: 2026-10-10T10:19:48.186856+00:00
- actor: claude-code
  id: 01m4jxmfq8y7z4h5drs8f1xr6g
  text: |-
    User decisions applied (2026-10-10): agentSpawn runs with inlineSettleGrace 0; no test agent loses `tools: Agent`; new self rule in code; description adds "do the task yourself" and drops the v3 exception sentences.

    Self rule (code): `ParentRun.agentID` (set by `AgentSessionMaker` from the run's definition). `AgentsToolContext.canStart` excludes `isOwnAgent(_:)`, thus the description list, `list agents`, and the `name` enum of a run's tool do not hold its own agent. `start agent` with the own name gives `AgentsToolText.ownAgent`: "You cannot start the agent <name>, because it is your own agent. Do this task yourself. The agents that you can start are: …". `send agent` with the own run id (`isOwnRun(_:)`: parent present and id == session of ToolContext.current) gives `AgentsToolText.ownRun`: "The id <id> is the id of your own run. You cannot send a message to your own run." A host root session (parent nil) is not affected. New unit tests: `AgentsToolSelfRuleTests` (4 tests, RED then GREEN). `NestedRunTests+Limits.childAtMaxDepthHasTheMessagingTool` had `planner` start `planner`; the self rule forbids that, thus the child is now `flash-lead` (an `Agent` entry); the asserts did not change.

    Live harness: `LiveHarness.withHarness(inlineSettleGrace:)` (default `ToolMount.defaultInlineSettleGrace`) sets the root session and the runner; LiveNested agentSpawn passes 0. No assert changed.

    Final pass counts, N = 10, Router pinned 16abef2d:
    | test | before | v3 | final |
    | FullCircle exact JSON | 10 | 10 | 9 |
    | FullCircle tool description | 9 | 9 | 10 |
    | LiveNested agentSpawn | 0 | 0 | 10 |
    | LiveNested message | 10 | 8 | 10 |
    The one final failure (run 4, FullCircleTests.swift:100 `rejected.isEmpty`): the Router rejected the first tool call of the 27B root as `malformed_syntax` in the exact-JSON case; the retry made the correct call and the rest of the circle passed. It is the same failure class as before-run 5 (Router tool-call parse of the 27B output), not the description.

    ### implement — changed
    - evidence: `swift test` 497 tests in 67 suites passed; `swift build --package-path IntegrationTests --build-tests` exit 0 (both with one SwiftPM "missing creator for mutated node" warning for the mlx Cmlx.bundle). Live N=10 counts above. Files: Sources/FoundationModelsAgents/Run/AgentRun+Children.swift, Run/AgentSessionMaker.swift, Tool/AgentsToolContext.swift, Tool/AgentsToolOperations.swift, Tool/AgentsToolText.swift, Tool/AgentsToolDescription.swift, FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md, README.md, Tests/FoundationModelsAgentsTests/AgentsToolDescriptionTests.swift, AgentsToolSelfRuleTests.swift (new), NestedRunTests+Limits.swift, IntegrationTests/.../Support/LiveProfile.swift, Support/LiveHarness.swift, LiveNestedTests.swift.
    - next: /review. Acceptance "N of N" holds for 3 of 4 tests; FullCircle exact JSON 9/10 from one Router malformed_syntax rejection.
  timestamp: 2026-10-10T12:47:02.376739+00:00
position_column: done
position_ordinal: cf80
title: 'Agents tool description: Qwen models find and use a matching sub-agent every time'
---
## What

The live nested test fails often: `IntegrationTests/Tests/AgentsIntegrationTests/LiveNestedTests.swift:110` ("agentSpawn links three sessions…") gives `!leadStartAnswers.isEmpty`. The model of the lead run does not call `start agent` for the leaf agent. The test failed on CI for 22212fb (run 37819994966) and for dfd406b (run 37999003001). An earlier run (6649406, run 37738884153) failed in FullCircleTests.swift:109, where the root did not start the sub-agent from the tool description.

The user decided (2026-10-10): test with Qwen, and write a tool description that is good enough so that the models consistently search the agents and use a matching sub-agent for a matching task.

## Facts

- The live profile already uses Qwen: `standard` = `mlx-community/Qwen3-4B-4bit`, `flash` = `mlx-community/Qwen3-1.7B-4bit`, embedding = `mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ` (`IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveProfile.swift:55-60`). Check which slot each live run uses. A run with no `model` key inherits the slot of its caller. If the user means another Qwen model (for example a larger one), ask before you change the profile.
- The description text is in `Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift` (`fixedSentences`, `delegationSentence`, the agent list forms, `notListedNote`). The pinned text test is `Tests/FoundationModelsAgentsTests/AgentsToolDescriptionTests.swift`.
- The agent list in the description gives name and description of each agent. `list agents` gives the full list when the description cuts it.

## Work

1. Measure first. Run the failing live tests (LiveNestedTests, FullCircleTests) N times each (for example 10) with the current text, and record the pass count. Use the IntegrationTests package and `swift test --filter`.
2. Change the description so that the model:
   - knows that it must match a task to an agent by the agent description, and call `start agent` when one matches, in place of doing the task itself;
   - uses `list agents` when the list is cut or when no listed agent matches;
   - gives the full task in the prompt.
   Keep the text short and in ASD-STE100. Keep the op-name rule (the model calls the tool, not "start agent" as a tool).
3. Measure again with the same N. The target: the live tests pass every time in N runs. Record both counts in a comment on this task.
4. Do not make a test pass by weakening it. If a test asks for something that a 1.7B model cannot do, report it, and propose the slot or model change.
5. Update the pinned text test, the README, and the DocC text that quotes the description.

## Acceptance criteria

- [ ] Pass counts before and after are recorded (N runs of each live test).
- [ ] LiveNestedTests and FullCircleTests pass in N of N runs with the new description.
- [ ] `swift test` passes. The IntegrationTests package builds.
- [ ] CI "Integration (opt-in, real dependencies)" passes for the commit.