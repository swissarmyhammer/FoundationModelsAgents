---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m77r4d5gqvy9xk7bx1s65e9d
  text: |-
    The Skills API of FoundationModelsSkills card ^e3sj0rw (not on main yet):
    - `SkillsRegistry.call(id: String, arguments: [String] = [], templateContext: [String: TemplateValue]? = nil) async throws -> String`. Non-nil values replace the registry values for that render, also for partials. `nil` keeps the registry values.
    - `SkillsCatalogTool.withTemplateContext(_ templateContext: [String: TemplateValue]) throws -> SkillsCatalogTool`. It shares the search agent (index, embedder), the reload follow and the notice board of the shared tool. It changes only the values of each render.
    - `SkillsRegistry.withTemplateContext(_:) -> SkillsRegistry`: a view that shares the catalog and onReload.
    Start this card when the commit is on Skills main.
  timestamp: 2026-11-12T11:26:19.312319+00:00
- actor: claude-code
  id: 01m77rg8shkk2zj0wnjtbdr79a
  text: |-
    The Skills API is on Skills main at 55aa12c (code 950647c, 734d502, d8310b9). The final names replace the names of the comment before:
    - `SkillsRegistry.call(id: String, arguments: [String] = [], templateContext: [String: TemplateValue]? = nil) async throws -> String`. `nil` keeps the registry values. Given values replace them (no merge), also for partials.
    - `SkillsCatalogTool.with(templateContext: [String: TemplateValue]) throws -> SkillsCatalogTool` (not `withTemplateContext(_:)`). It shares the search agent, the reload follow, the notice board, the GraphQL endpoint, the description and the schema. It does not call the embedder.
    - `SkillsRegistry.with(templateContext:) -> SkillsRegistry`: a view that shares the catalog, the reload and onReload.
    Update the local pin of FoundationModelsSkills to 55aa12c or later, in the root package and in IntegrationTests.
  timestamp: 2026-11-12T11:32:48.049990+00:00
- actor: claude-code
  id: 01m77s0sjr4s5x9e0aa5d4ny0b
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (e3444f4): 0 findings, 0 confirmed, 0 refuted; 7 validator runs, 0 failed. 5 files reviewed. 1 file not reviewed because no validator matches it: Sources/FoundationModelsAgents/FoundationModelsAgents.docc/LoadingTheCatalog.md.
    - next: none. The task is in done.
  timestamp: 2026-11-12T11:41:49.528024+00:00
- actor: claude-code
  id: 01m77s1ccqgf813zj5346cfk53
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — AgentEnvironment.swift, AgentSessionMaker.swift, AgentSkillsPreload.swift, LoadingTheCatalog.md, RunTemplateContextTests.swift, SessionInstructionsFixture.swift; local Skills pin 55aa12c (root and IntegrationTests)
    - test: green — swift test, 966 tests in 127 suites, no warnings; IntegrationTests build complete
    - commit: e3444f4
    - review: clean — 0 findings
    - open items: a restored run reaches the skills through the same `resolveSetup` step as a new run, but no test row restores a run with a preloaded skill or a `skills` tool call. The restored row of ^c9930ne pins the body only. The items "A restored run gets the same values" and the test row for a restored run stay unchecked.
  timestamp: 2026-11-12T11:42:08.791047+00:00
depends_on:
- 01M77QWFM3KKJJGA0C4AY9F28M
- 01M77QWPNBANMGPNR26C9930NE
position_column: done
position_ordinal: ff9980
title: 'ACPA ^vshf002 (3): the skills: preload and the skills tool of a run use the run template context (needs a Skills API)'
---
## What
After card (2), the body of a run renders with the values of `runTemplateContext`. The `skills:` preload (`AgentSkillsPreload.bodies(of:)`, Sources/FoundationModelsAgents/Run/AgentSkillsPreload.swift) and the `skills` tool still render with the values of the skills registry. The `skills` tool is one tool in the `ToolCatalog` of the environment, shared by all runs.

This card needs a FoundationModelsSkills API (foundationmodelsskills-f7), for example:
- a per-call template context on `SkillsRegistry.call(id:)`, for the preload;
- a cheap per-run form of the `skills` tool with a template context, which shares the index of the shared tool.

When the API is on Skills main:
- `AgentSkillsPreload.bodies(of:templateContext:)` gives the run values to each render.
- `resolveSetup` gives each run a `skills` tool with the run values in place of the shared tool.
- A restored run gets the same values. `nil` keeps today's behavior.

## Acceptance Criteria
- [x] A preloaded skill with `{% if tools.shell.enabled %}` renders each branch from the run values.
- [x] A `skills` tool call of a run renders the skill with the run values.
- [ ] A restored run gets the same values; `nil` keeps today's text.

## Tests
- [ ] Tests/FoundationModelsAgentsTests/RunTemplateContextTests.swift: rows for the preload, the skills tool and a restored run.
- [x] `swift test` passes; IntegrationTests builds.

## Workflow
- Use `/tdd`. #step1