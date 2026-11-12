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
depends_on:
- 01M77QWFM3KKJJGA0C4AY9F28M
- 01M77QWPNBANMGPNR26C9930NE
position_column: todo
position_ordinal: '8280'
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
- [ ] A preloaded skill with `{% if tools.shell.enabled %}` renders each branch from the run values.
- [ ] A `skills` tool call of a run renders the skill with the run values.
- [ ] A restored run gets the same values; `nil` keeps today's text.

## Tests
- [ ] Tests/FoundationModelsAgentsTests/RunTemplateContextTests.swift: rows for the preload, the skills tool and a restored run.
- [ ] `swift test` passes; IntegrationTests builds.

## Workflow
- Use `/tdd`. #step1