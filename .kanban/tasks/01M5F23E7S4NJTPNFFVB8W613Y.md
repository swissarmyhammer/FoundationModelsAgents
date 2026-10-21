---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f488rcxrap0kydmqvrywqr
  text: |-
    Research (implement step):
    - Extras updated to 11ffe56 (EXTRAS-10). Toolkit: GraphQLRunContext, addToolkitScalars, API.respond/subscribe, GraphQLNameRules/GraphQLAliasTable, CodedError, GraphQLSchemaGolden/Descriptions/EndpointConformance. Extras pins GraphQL from 4.3.0, Graphiti from 3.1.0 (https://github.com/GraphQLSwift/...). GraphQLEndpointConformance at 11ffe56 has NO rule-9 check and NO exception parameter (EXTRAS-11 is still proposed), so the AG-8c exception is a named filter in the test over any problem about `changes`/`cursor`.
    - The port is the AgentRegistry (rule 1: one endpoint per registry). `list agents` read `runner.catalog()`, which rebuilds the run warnings (model/tool/skill) for every definition on each call; the definitions are the registry's. The move: `AgentsToolContext.startableAgents()` reads `runner.registry.catalog()`.
    - `start agent` matches the name exactly (`$0.id == name`), so `agent(id:)` accepts the exact canonical id, through `AgentCatalog.definition(named:)`.
    - `AgentDiagnostic` has no code. Each finding gets an `AgentDiagnostic.Code` (UPPER_SNAKE raw value). "conflict copy" has no diagnostic of its own: `AGENT 2.md` is a resource (LoadingTheCatalog.md). The copy conflict that IS reported is the hidden-copy advisory (two layers hold one id) -> `HIDDEN_COPY`. Duplicate default = the hidden `default/` folder warning -> `DUPLICATE_DEFAULT`. Not-local placeholder -> `NOT_LOCAL`. Missing description -> `MISSING_DESCRIPTION`.
    - Before `load()` the registry gives an empty catalog; the endpoint refuses with `CATALOG_NOT_LOADED` (AgentsGraphError) rather than claim an empty catalog.
  timestamp: 2026-10-21T11:41:26.156753+00:00
- actor: claude-code
  id: 01m5f526nqhv4a0vpb0qx13p2v
  text: |-
    Implementation landed (not committed):
    - New Sources/FoundationModelsAgents/Graph/: AgentsGraph (GraphQLEndpoint, name agents, version 1, scope sessionFolder, alias rules), AgentsGraphSchema (context, resolver over AgentRegistry, Graphiti API), AgentsGraphTypes (Agent, AgentLayer, AgentMarketplace, AgentDiagnostic, enums), AgentsGraphError (CATALOG_NOT_LOADED, `AgentsGraphError.codes` is the one code list).
    - Ids are String! not ID!, per coordinator: comment names ^70231sy (toolkit ID scalar). No local ID scalar (rule 2).
    - Port: AgentsToolContext.startableAgents() and StartAgent.unavailableText read runner.registry.catalog() (no more per-call run-warning rebuild of runner.catalog()).
    - Diagnostics: AgentDiagnostic.Code (26 UPPER_SNAKE cases, Definition/AgentDiagnosticCode.swift); AgentFinding/AgentDiagnostic carry a code; every finding site sets one. "conflict copy" maps to HIDDEN_COPY (a conflict copy like `AGENT 2.md` gives no diagnostic; it is a resource).
    - Alias: standard query verb `find` gives the plural field, so the rules drop `find` from queryVerbs and alias findAgent->agent, findAgents->agents.
    - Conformance test uses the EXTRAS-11 API (Extras 02a207c): codes: AgentsGraphError.codes, exceptions: [GraphQLConventionException(rule: .changes, removedBy: "^20mv6d3")]. Note: the rule-9 case is `.changes`, not `.rule9`.
    - Graphiti gotcha: SchemaBuilder.add/addQuery result builders take single components only, so each type/field is its own static func.
    - Golden at Tests/Fixtures/agents.graphql.
  timestamp: 2026-10-21T11:55:35.991220+00:00
- actor: claude-code
  id: 01m5f52a9q619sjtzk155148ct
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` 0 warnings/errors; `swift test` 641 tests in 89 suites passed (19 new in "Agents graph" + "Agents graph diagnostics"). Files: Package.swift; Sources Graph/{AgentsGraph,AgentsGraphSchema,AgentsGraphTypes,AgentsGraphError}.swift, Definition/{AgentDiagnosticCode,AgentDiagnostic,AgentDefinitionRules,AgentAccessKey}.swift, Registry/AgentCatalogBuilder.swift, Run/{AgentRunner,AgentSkillsPreload}.swift, Tools/{ToolResolver,ToolSelection}.swift, Tool/{AgentsToolContext,AgentsToolOperations}.swift; Tests AgentsGraphTests, AgentsGraphDiagnosticTests, Support/{AgentsGraphFixture,GraphQLReply}.swift, 4 existing tests (diagnostic code), Tests/Fixtures/agents.graphql.
    - next: /review
  timestamp: 2026-10-21T11:55:39.703660+00:00
- actor: claude-code
  id: 01m5f5545cjxn3yekv5m4ytf7z
  text: |-
    ### test — green
    - evidence: swift test — 641 tests in 89 suites passed, 0 failed, 0 skipped; forced full recompile of Sources and Tests (swift build --build-tests) gave zero compiler warnings. Only output is the SwiftPM build-system line "missing creator for mutated node ... mlx-swift_Cmlx.bundle", from the mlx-swift dependency bundle, not from package code.
    - next: review
  timestamp: 2026-10-21T11:57:11.724640+00:00
position_column: doing
position_ordinal: '80'
title: 'AG-8a AgentsGraph: the agents and agent(id:) queries over the catalog of the session folder'
---
## What
Add the `agents` GraphQL endpoint (AG-8, features/packages/foundationmodels-agents.md:94) to the FoundationModelsAgents library target, under the shared conventions EXTRAS-9 (features/packages/foundationmodels-extras.md:91, D115). Reference implementation: `SettingsGraph`/`SettingsGraphSchema`/`SettingsGraphError` in FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Settings/.

- `AgentsGraph: GraphQLEndpoint`, `name = "agents"`, `version = "1"`, `scope = .sessionFolder`. The endpoint reads the catalog of one `AgentRegistry`; the host keeps one registry for each session folder (AG-10: the session folder is the project layer), so the catalog is the one the session of the call sees. This answers D87 (a).
- A port that both the `list agents` operation and the resolvers call (EXTRAS-9 rule 1), so the op tool and the endpoint give the same data. Move the read of `ListAgents` onto it.
- Queries (rule 5, flat root): `agents: [Agent!]!` and `agent(id: ID!): Agent` which is `null` for an unknown id. The input accepts the forgiving forms that `start agent` accepts; the output `id` is the canonical `AgentDefinition.id` (rule 6, the form of ^jcnw05g).
- `Agent`: `id: ID!`, `description`, `model`, `color`, `background`, `isModelVisible`, `isUserInvocable`, `isDefault`, the source layer (name/root) and the marketplace provenance when any. Every type and field has a description.
- Diagnostics: the catalog diagnostics (missing description, not-local placeholder, conflict copy, duplicate default) are the data the manager view needs (APP-12); give them as `Agent.diagnostics` and a root `diagnostics` list with `UPPER_SNAKE` codes.
- No mutation (D84). No subscription here: it is task AG-8c, blocked on EXTRAS-10.
- Engine (rule 2): only the toolkit — a `GraphQLRunContext`, `addToolkitScalars()`, `respond`/`subscribe`, `GraphQLNameRules` with the alias tables of the package, and a package `CodedError` type (`AgentsGraphError`). Extras does not re-export GraphQL/Graphiti, so Package.swift declares `GraphQL` and `Graphiti` from the same URLs and floors as Extras (as FoundationModelsACPAgent does), and no other copy.
- Alias tables (D86): `agent(name:)` → `agent(id:)`; `name`/`agentName` → `id` in each input; `listAgents`/`allAgents` → `agents`; `getAgent`/`findAgent` → `agent`.

## Acceptance criteria
- [ ] `AgentsGraph` conforms to `GraphQLEndpoint` with name `agents`, version `1`, scope `sessionFolder`.
- [ ] `agents` and `agent(id:)` give the catalog of the registry; an unknown id gives `null`, not an error.
- [ ] `list agents` and the resolvers read one port.
- [ ] No mutation in the schema.
- [ ] Package.swift declares GraphQL/Graphiti from the Extras URLs only.

## Tests (EXTRAS-9 rule 11)
- [ ] `GraphQLSchemaGolden` test of the SDL.
- [ ] `GraphQLSchemaDescriptions.undescribed` is empty.
- [ ] `GraphQLEndpointConformance.problems` is empty with an alias probe (`agent(name:)` → `agent(id:)`), with the rule-9 `changes`/`cursor` checks listed as an exception that names AG-8c.
- [ ] Resolver tests over a temporary layer stack (`TemporaryLayer`): list, one agent, unknown id → null, the default agent, a diagnostic. #AG-8