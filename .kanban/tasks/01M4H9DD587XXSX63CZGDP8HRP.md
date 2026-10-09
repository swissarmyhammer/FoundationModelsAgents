---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4h9efsw7wtyp6erwvwkabk4
  text: '2026-10-09: Follow the pattern of FoundationModelsACPAgent (the user named it). In `Sources/FoundationModelsACPAgent/Agent/SessionSetup.swift:652-664`, the host makes ONE watched registry (`ToolCatalog.makeSkillsRegistry(context:)`) and gives that same instance to the instructions preload (`InstructionsAssembler.assemble(skills:)`), to the skills tool (`ToolCatalog.sessionSurface(context:skillsRegistry:)` → `makeSkillsTool(context:registry:)`, ToolCatalog.swift:204-212), and to the slash-command providers. ACPAgent does not use FoundationModelsAgents yet. AgentEnvironment must make the same thing true for the runs: the registry that the host gives is the registry of the `skills` tool of each run and of the `skills:` preload.'
  timestamp: 2026-10-09T21:34:59.900344+00:00
- actor: claude-code
  id: 01m4h9h1ckcy4ejjm9gfjm5pha
  text: '2026-10-09: FoundationModelsACPAgent task ^c4a6mwy (01M4GMGDMSF9PC9RWKKC4A6MWY, "Mount the standalone agents tool beside the skills tool") waits on this task. It uses AgentEnvironment and the skills tool. When this task is pushed, tell the ACPAgent session (foundationmodelsacpagent-3d) the final API.'
  timestamp: 2026-10-09T21:36:23.443440+00:00
- actor: claude-code
  id: 01m4hapxpxbh1b1gwhzeemnjfb
  text: |-
    Research (2026-10-09):
    - SkillsRegistry is a struct. Its copies share one private CatalogBox. Thus `===` is not possible. The identity test uses a `watch: true` registry: a skill that is written after the environment is made must show in the tool of the catalog, in `environment.skillsTool`, and in the preload. A tool from a different registry (watch: false) does not see it.
    - SkillsCatalogTool keeps its context private. The tool name comes from `skillsTool.name` ("skills"). `SkillsTool.toolName` is internal in Skills.
    - ACPAgent uses `SkillsTool.make(registry:model:)` with its own `RoutedSelectionModel` (not public, in ACPAgent). Thus AgentEnvironment takes an optional `any LanguageModel`. With no model, it uses `SkillsTool.make(registry:)` (retrieval only), as the README did.
    - The `initialization` Swift rule says "init does no slow work". SkillsTool.make builds an index. Thus the public entry is `static func make(...) async throws -> AgentEnvironment`, and the memberwise init becomes internal (it takes the made tool). The test harness (AgentRunHarness) makes the tool one time in `make` and uses the internal init, so its sync `makeRunner()` callers do not change.
    - Tool names match by exact string (ToolSelection), thus the check is for the exact name `skills`.
  timestamp: 2026-10-09T21:57:04.861837+00:00
- actor: claude-code
  id: 01m4hbnbvxf9fd7p8f9evnpzsn
  text: |-
    Implementation (2026-10-09):
    - API decision: the public `AgentEnvironment.init` is gone. The host calls `public static func make(profile:skills:skillsSelectionModel:skillsCatalogCharacterLimit:skillsVisibility:workingDirectory:tools:defaultSlot:maxConcurrentAgents:maxDepth:maxRetainedRuns:budget:tracer:logger:metricsFactory:inlineSettleGrace:) async throws -> AgentEnvironment`. Reason: `SkillsTool.make` is async throws, and the Swift rule "init does no slow work" forbids the index build in an init. The memberwise init is internal, takes the made tool, and the test harness uses it.
    - New public members: `skillsTool: SkillsCatalogTool`, `typealias SkillsVisibility = @Sendable (SkillMetadata) -> Bool`, `static let defaultSkillsVisibility` (`isModelVisible`). Internal: `skillsVisibility`, `skillsPreload`, `static func makeSkillsTool(...)`.
    - With `skillsSelectionModel: nil` the tool comes from `SkillsTool.make(registry:catalogCharacterLimit:visibilityPredicate:)` (retrieval only, as the old README). With a model it comes from `SkillsTool.make(registry:model:...)`, the overload of ACPAgent (ACPAgent gives its `RoutedSelectionModel`).
    - The environment registers the tool in its `ToolCatalog` under `skillsTool.name` ("skills"). A host `skills` entry stops the process (precondition, the same as the other programmer errors of this type).
    - `AgentSkillsPreload` takes the visibility rule of the tool. The hidden-skill warning text did not change.
    - Behavior change: each run with no `tools` key now gets the `skills` tool (it is in the catalog). Four tests that pinned exact tool-name lists now include `skills` (AgentsToolMountTests, NestedRunTests+Limits). The agents-demo fan-out run showed a run that called the `skills` tool.
    - What did not work: `ScriptedAgentModel` as the selection model. It has only `.toolCalling`, so the SDK refuses the guided `Selection` request before the executor runs. A new test support `SelectionProbeModel` (guided generation, counts calls) replaced it.
  timestamp: 2026-10-09T22:13:42.397275+00:00
- actor: claude-code
  id: 01m4hbngfpnqvm4yyzrd0wswbf
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` 0 warnings (only the mlx "missing creator" note); `swift test` 493 tests in 66 suites passed; `swift build --package-path IntegrationTests --build-tests` Build complete, 0 warnings of ours; `agents-demo --fan-out` ran (code-reviewer finished, test-writer called the skills tool, then was cancelled at end of input). 24 files: Sources/FoundationModelsAgents/Run/AgentEnvironment.swift, Run/AgentSkillsPreload.swift, Run/AgentSessionMaker.swift, Run/AgentRunner.swift, Tools/ToolCatalog.swift, docc/RunningAnAgent.md, docc/FoundationModelsAgents.md, docc/DelegatingWithTheAgentsTool.md, README.md, docs/skills-and-agents.md, Examples/agents-demo/DemoModes.swift, Tests/.../SkillsToolSharingTests.swift (new), Tests/.../Support/SelectionProbeModel.swift (new), Tests/.../Support/AgentRunHarness.swift, AgentEnvironmentTests.swift, AgentsToolMountTests.swift, NestedRunTests+Limits.swift, ReadmeExampleSource.swift, IntegrationPackageTests.swift, IntegrationTests/.../LiveProfile.swift, LiveHarness.swift, LiveSourcesTests.swift.
    - next: /review. Then tell ACPAgent (^c4a6mwy) the final API when pushed.
  timestamp: 2026-10-09T22:13:47.126873+00:00
- actor: claude-code
  id: 01m4hc3tbm43s5h1f6qdsgnk0z
  text: |-
    ### review — findings
    - evidence: `review working` vs HEAD f3cbf03; counts: 2 findings (2 confirmed, 3 refuted, 14 attempted, 0 failed). Examples/agents-demo/DemoModes.swift:337, IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveProfile.swift:103 (duplication/duplication). Not reviewed (no validator matched): README.md, the 3 DocC files, docs/skills-and-agents.md.
    - next: /implement the open items in "Review Findings (2026-10-09 17:14)", then /review again.
  timestamp: 2026-10-09T22:21:35.988811+00:00
- actor: claude-code
  id: 01m4hc4dacf39csfy0a3gr8yr6
  text: |-
    ### review findings — no change needed
    - Examples/agents-demo/DemoModes.swift:337 and IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveProfile.swift:103: not changed. Each `makeRunner` is a 3-line wrapper around `AgentEnvironment.make` + `AgentRunner(...)`, in two different packages (the demo executable and the separate IntegrationTests package). They also differ: the demo calls `registry.load()` and passes `inlineSettleGrace`. A shared helper would need a new public library API only for a demo and a test. The shared part is already one call, `AgentEnvironment.make`.
    - evidence: `swift test` 493 tests in 66 suites passed; IntegrationTests builds (implement step record).
    - next: commit.
  timestamp: 2026-10-09T22:21:55.404777+00:00
position_column: done
position_ordinal: ce80
title: One SkillsRegistry instance for the skills tool and the agents
---
## What

Now the host gives the skills two times. It gives `AgentEnvironment(skills: SkillsRegistry)`, which the `skills:` preload reads. It also gives `tools.register("skills") { skillsTool }` in the `ToolCatalog`, which the runs call. The tool can come from a different registry, with different marketplaces and paths. Then an agent can preload a skill that its `skills` tool does not show, or the opposite.

The user decided (2026-10-09): the `skills` tool and the agents (the `skills:` preload, and the `agents` tool that starts the runs) share ONE `SkillsRegistry` instance. The agents must not guess.

## Design

- `AgentEnvironment` keeps `skills: SkillsRegistry` as the one source.
- The environment makes the `skills` tool from that registry (`SkillsTool.make(registry:)`) and puts it in its `ToolCatalog` under the name `skills`. The host does not register a `skills` entry. A host `skills` entry in the catalog is a programmer error: throw or reject it at init, and test it.
- Give the tool to the host as `environment.skillsTool` (or an equivalent), so the root session of the host uses the same tool instance, thus the same registry.
- If the host needs tool options (search agent, catalog character limit, visibility predicate), take them as init parameters of `AgentEnvironment` and pass them to `SkillsTool.make`. Use the same visibility rule for the preload (`AgentSkillsPreload`), so that a skill the tool hides is not preloaded.
- `AgentEnvironment.init` may need to become `async throws`, because `SkillsTool.make` is `async throws`. If so, choose the smallest change (for example a static `make` function), and say it in the report.
- No change in FoundationModelsSkills is necessary.

## Changes here

- `Sources/FoundationModelsAgents/Run/AgentEnvironment.swift` (line 43, the init at line 157).
- `Run/AgentSkillsPreload.swift`, `Run/AgentSessionMaker.swift:53`, `Run/AgentRunner.swift:340`.
- `Tools/ToolCatalog.swift` (the doc example at line 11).
- The 9 files that call `AgentEnvironment(`: Sources, Tests, Examples/agents-demo, IntegrationTests.
- README, DocC (`RunningAnAgent.md:20-25`, `FoundationModelsAgents.md`), `docs/skills-and-agents.md`, `ReadmeExampleSource.swift`.

## Acceptance criteria

- [x] The host gives one `SkillsRegistry`. The runs get the `skills` tool made from it, and the preload reads the same instance (test with `===` or an equivalent identity check).
- [x] The host root session can get the same skills tool from the environment.
- [x] A host `skills` entry in the `ToolCatalog` is rejected, with a test.
- [x] A skill that the tool hides is not preloaded, and gives the hidden-skill warning.
- [x] The README example and its test agree.
- [x] `swift build` and `swift test` pass with no warnings.

## Review Findings (2026-10-09 17:14)

> Scope: `review working` — reviewed the diffs only — lines this change added or modified. 17 file(s) reviewed, 7 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 5 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/FoundationModelsAgents.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/RunningAnAgent.md` — no validator matches this file
> - `docs/skills-and-agents.md` — no validator matches this file

- [ ] `Examples/agents-demo/DemoModes.swift:337` `duplication/duplication` — The new makeRunner copies the environment setup of LiveProfile.makeRunner. Both build AgentEnvironment.make from the profile, an empty SkillsRegistry, and a working directory, then wrap it in an AgentRunner. A fix to one copy can drift from the other. Move the shared setup into one helper, for example a static func that takes the profile, registry, working directory, and any extra options, and call it from both sites. Delete the copy the change added here. Keep the test-only tools parameter at the test call site.
- [ ] `IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveProfile.swift:103` `duplication/duplication` — The new makeRunner copies the environment setup of DemoModes.makeRunner. Both build AgentEnvironment.make from the profile, an empty SkillsRegistry, and a working directory, then wrap it in an AgentRunner. Share one helper with the demo copy, as described for DemoModes.swift:337. Delete the copy that this change added in one of the two files, and have the other call the shared helper.
