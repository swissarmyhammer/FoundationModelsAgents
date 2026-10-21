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
- actor: claude-code
  id: 01m5f5gqdsn8qbgps042cxkabd
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (0579ae2): 0 findings, 0 confirmed, 0 refuted (14 validator runs, 0 failed); 24 files reviewed; .kanban/ ignored, Tests/Fixtures/agents.graphql had no matching validator. Acceptance criteria 5/5 and tests 4/4 ticked against the code: AgentsGraph name/version/scope (Graph/AgentsGraph.swift); list agents (AgentsToolContext.startableAgents) and the resolvers (AgentsGraphSchema) both read registry.catalog(); no Mutation in Tests/Fixtures/agents.graphql (theSchemaHasNoMutation); Package.swift GraphQL 4.3.0 / Graphiti 3.1.0 match the FoundationModelsExtras pins; golden, undescribed, conformance with agent(name:) probe and the .changes exception naming ^20mv6d3, and TemporaryLayer resolver and diagnostic tests in AgentsGraphTests and AgentsGraphDiagnosticTests. The output id is `String!`, not the `ID!` of the What section, per the coordinator and the comment naming ^70231sy.
    - next: done
  timestamp: 2026-10-21T12:03:31.897438+00:00
- actor: claude-code
  id: 01m5f5hsfy211tpqesttnc88dx
  text: |-
    ### finish iteration 1 — clean, reopened
    - implement: changed — Graph/*, AgentDiagnosticCode, Package.swift, 19 new tests
    - test: green — swift test, 641 tests in 89 suites, 0 warnings
    - commit: 0579ae2
    - review: clean — 0 findings (24 files)
    - reopened by the orchestrator: the spec's `id: ID!` was deferred to ^70231sy, which has now landed in Extras 9c47e10. One finding added; back to review.
  timestamp: 2026-10-21T12:04:06.782338+00:00
- actor: claude-code
  id: 01m5f5j5h5p8yt7hgxmkrx144j
  text: |-
    ### review — findings
    - evidence: This record replaces the "review — clean" record above. The coordinator gave a new fact after the engine run: the toolkit ID scalar is on FoundationModelsExtras origin/main 9c47e10 (verified: `ToolkitID` in Sources/FoundationModelsExtras/GraphQL/Scalars.swift, `addToolkitIDScalar()` on SchemaBuilder). The engine result is unchanged (0 findings, 0 confirmed, 0 refuted). 1 finding: Sources/FoundationModelsAgents/Graph/AgentsGraphTypes.swift:11, `Agent.id` and `agent(id:)` are `String!` and must be `ID!`/`ToolkitID` per EXTRAS-9 rule 6. The fix also covers Tests/Fixtures/agents.graphql:52/:61/:134, AgentsGraphTypes.swift:13/:123/:151/:211 and Support/AgentsGraphFixture.swift:27. The acceptance criteria and test boxes stay ticked, because each holds as written.
    - next: implement — adopt Extras 9c47e10, call addToolkitIDScalar(), retype id to ID, update the golden, remove the ^70231sy comments; then test and review
  timestamp: 2026-10-21T12:04:19.109862+00:00
- actor: claude-code
  id: 01m5f5txe210spqxx01z6zxste
  text: |-
    ID finding (spec/EXTRAS-9-rule-6) done:
    - `swift package update FoundationModelsExtras` resolved Extras to 9c47e10. Package.resolved is in .gitignore (`.gitignore` Package.resolved), so the pin is local only and nothing in git changes for it. The Package.swift dependency is `branch: main`, so a fresh resolve gets 9c47e10 or later.
    - AgentsGraphAPI calls `.addToolkitIDScalar()` after `.addToolkitScalars()`. ToolkitID is now the Swift type of every id field: `Agent.id`, `AgentMarketplace.id` (golden line 52, in the finding), `AgentDiagnostic.agent` (the agent id in a diagnostic), and the `agent(id:)` argument. The resolver reads `arguments.id.text`.
    - Golden: the scalar keeps the built-in name `ID`, so printSchema prints no `scalar ID` line, and only the four type lines change. I hand-edited the golden first (RED), then ran `GRAPHQL_GOLDEN_RECORD=1` (GraphQLSchemaGolden.recordVariable). The recorded file is byte-identical to the hand edit.
    - Every ^70231sy comment is gone: 5 in AgentsGraphTypes.swift, 1 in AgentsGraphFixture.swift. No exception for ^70231sy existed (the one conformance exception is `.changes` for ^20mv6d3, and it stays). `rg 70231sy` outside .kanban finds nothing.
    - New input form: `agent(id: 42)` (an Int literal) finds the agent whose folder is `42` (valid: [a-z0-9-]), and the output id is the String "42". Test: AgentsGraphTests.anIntIDFindsTheAgentOfItsDecimalText. The alias probe `agent(name:)`, `getAgent`/`findAgent(agentName:)` and `listAgents` still pass. The fixture query variable is now `$id: ID!`.
    - The card has one `## Review Findings` section (2026-10-21 07:05) with one item. The coordinator said two sections; the description holds only that one, and it is ticked.
  timestamp: 2026-10-21T12:09:05.730084+00:00
- actor: claude-code
  id: 01m5f5v0y1my516yb1dp1mcv06
  text: |-
    ### implement — changed
    - evidence: 5 files. Sources/FoundationModelsAgents/Graph/{AgentsGraphTypes,AgentsGraphSchema}.swift; Tests/Fixtures/agents.graphql (regenerated with GRAPHQL_GOLDEN_RECORD=1); Tests/FoundationModelsAgentsTests/AgentsGraphTests.swift (+1 test); Tests/FoundationModelsAgentsTests/Support/AgentsGraphFixture.swift. RED: 11 issues in the graph suites (Unknown type "ID", golden mismatch, Int literal refused). GREEN: 19 graph tests pass. Full `swift test`: 642 tests in 89 suites passed, 0 failed. `swift build --build-tests` gave 0 compiler warnings; the only output line is the SwiftPM mlx-swift bundle line. Findings 1/1 checked. Extras resolved to 9c47e10 (Package.resolved is gitignored).
    - next: /review
  timestamp: 2026-10-21T12:09:09.313300+00:00
- actor: claude-code
  id: 01m5f5x9m3fkzyv8pyqnff9v4g
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` complete; `swift test` — 642 tests in 89 suites passed, 0 failed, 0 skipped. No compiler warnings from this package. The only build output warning is a SwiftPM message about the dependency bundle mlx-swift_Cmlx.bundle ("missing creator for mutated node"), which comes from the build system and a dependency, not from package sources.
    - next: review
  timestamp: 2026-10-21T12:10:23.747089+00:00
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
- [x] `AgentsGraph` conforms to `GraphQLEndpoint` with name `agents`, version `1`, scope `sessionFolder`.
- [x] `agents` and `agent(id:)` give the catalog of the registry; an unknown id gives `null`, not an error.
- [x] `list agents` and the resolvers read one port.
- [x] No mutation in the schema.
- [x] Package.swift declares GraphQL/Graphiti from the Extras URLs only.

## Tests (EXTRAS-9 rule 11)
- [x] `GraphQLSchemaGolden` test of the SDL.
- [x] `GraphQLSchemaDescriptions.undescribed` is empty.
- [x] `GraphQLEndpointConformance.problems` is empty with an alias probe (`agent(name:)` → `agent(id:)`), with the rule-9 `changes`/`cursor` checks listed as an exception that names AG-8c.
- [x] Resolver tests over a temporary layer stack (`TemporaryLayer`): list, one agent, unknown id → null, the default agent, a diagnostic. #AG-8

## Review Findings (2026-10-21 07:05)

> Scope: `review sha HEAD~1..HEAD` (0579ae2). The engine gave 0 findings. The finding below comes from the coordinator: the toolkit ID scalar is now on FoundationModelsExtras origin/main (code 44c2f54, tip 9c47e10).

- [x] `Sources/FoundationModelsAgents/Graph/AgentsGraphTypes.swift:11` `spec/EXTRAS-9-rule-6` — The task spec requires `Agent.id: ID!` and `agent(id: ID!)`. Commit 0579ae2 uses `String!` (Tests/Fixtures/agents.graphql:52, :61, :134) and carries ^70231sy "until" comments (AgentsGraphTypes.swift:11, :13, :123, :151, :211; Tests/FoundationModelsAgentsTests/Support/AgentsGraphFixture.swift:27). Extras 9c47e10 provides `SchemaBuilder.addToolkitIDScalar()`, which registers the scalar `ID` with the Swift type `ToolkitID` (Codable as a string, expressible by a string literal, input String or Int, output String). Adopt Extras 9c47e10 (Package.resolved), call `addToolkitIDScalar()`, make `Agent.id` and the `agent(id:)` argument `ID`/`ToolkitID`, update the golden `Tests/Fixtures/agents.graphql`, and remove each ^70231sy comment and any exception for it.