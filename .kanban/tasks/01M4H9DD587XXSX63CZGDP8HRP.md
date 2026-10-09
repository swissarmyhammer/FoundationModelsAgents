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
position_column: todo
position_ordinal: '80'
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

- [ ] The host gives one `SkillsRegistry`. The runs get the `skills` tool made from it, and the preload reads the same instance (test with `===` or an equivalent identity check).
- [ ] The host root session can get the same skills tool from the environment.
- [ ] A host `skills` entry in the `ToolCatalog` is rejected, with a test.
- [ ] A skill that the tool hides is not preloaded, and gives the hidden-skill warning.
- [ ] The README example and its test agree.
- [ ] `swift build` and `swift test` pass with no warnings.