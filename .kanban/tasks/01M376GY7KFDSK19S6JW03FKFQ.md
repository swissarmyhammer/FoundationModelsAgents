---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37q9zdm2csv7qtnbaanxcwa
  text: |-
    Research:
    - The model is FoundationModelsSkills `SkillsTool.make` + `SkillsCatalogTool` + `SkillsToolSchema` + `SkillsToolDescription`. Those types are internal to Skills, thus this package needs its own copies for agents. Only `SkillsTool.defaultCatalogCharacterLimit` and `CorrectiveOutcome` are public.
    - `SchemaFusion.fuse` does not read `ParamMeta.allowedValues`. Thus the schema builder makes the fused shape itself and pins the `name` field to an enum of the visible agent names (an empty list keeps a plain string).
    - The `@Operation` macro needs `@Generable` on the struct (see Extras Examples/NotesTool). The body goes in an extension with `execute(in:)`.
    - `SkillsRegistry.truncatedForMenu` is internal. The 200-character cut is local here.
    - Verb aliases and the plain-text decode belong to the next task (^gbdqnnn).
    - The tool name is `ToolVocabulary.agentsToolName` ("agents").
  timestamp: 2026-09-23T18:09:05.972456+00:00
- actor: claude-code
  id: 01m37qjzfcnw48b7dx5n33b1ek
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsAgents/Tool/{AgentsTool,AgentsToolContext,AgentsToolOperations,AgentsToolDescription,AgentsToolSchema}.swift, Tests/FoundationModelsAgentsTests/{AgentsToolDescriptionTests,AgentsToolSchemaTests}.swift, Tests/FoundationModelsAgentsTests/Support/AgentsToolHarness.swift. `swift test --filter "AgentsToolDescriptionTests|AgentsToolSchemaTests"`: 19 tests pass. swiftlint: 0 violations.
    - note: the op of the list operation is `list agents` (noun `agents`), as plan §9.1 and the card say. The other three have the noun `agent`. The CLI task (§9.4 says `agents agent list`) must add a noun alias or accept this shape.
    - first try: the partial-form tests used short names, so form 3 (names only) fitted first. The tests now use long names.
    - next: test
  timestamp: 2026-09-23T18:14:00.940716+00:00
- actor: claude-code
  id: 01m37qm6p14mzmh0mbshers4n1
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 191 tests in 24 suites pass, 0 failed, 0 skipped (the guard tests are in this run); `swiftlint lint --quiet Sources Tests Examples` — 0 violations. The mlx-swift "missing creator" note is not ours.
    - next: commit
  timestamp: 2026-09-23T18:14:41.089048+00:00
depends_on:
- 01M376GQ5AB99BJYWHWW67DVCR
position_column: doing
position_ordinal: '80'
title: 'AgentsTool.make: the operation declarations, the description forms, the pinned schema'
---
## What
Plan.md §9.1, the tool surface. The operation bodies come in the next task.

- Create `Sources/FoundationModelsAgents/Tool/AgentsToolContext.swift`: `public struct AgentsToolContext: Sendable` with `runner` and an optional allowed-name limit (for `Agent(a, b)`).
- Create `Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift` with the four `@Operation` declarations and their parameters only: `list agents` (`filter?`), `start agent` (`name`, `prompt`), `check agent` (`id?`), `cancel agent` (`id`). Each body gives a fixed `.corrective("not implemented")` until the next task.
- Create `Sources/FoundationModelsAgents/Tool/AgentsTool.swift`: `public struct AgentsTool: Tool` that wraps an `OperationTool<AgentsToolContext>`, as `../FoundationModelsSkills/Sources/FoundationModelsSkills/Operations/SkillsCatalogTool.swift` does. `public static func make(context:catalogCharacterLimit: Int = SkillsTool.defaultCatalogCharacterLimit) async throws -> AgentsTool` reads the catalog one time. The pinned schema is built from the fused schema of the operations, as `SkillsToolSchema.make(name:operations:skillIDs:)` does.
- Create `Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift`: the fixed sentences of §9.1 (never cut), then the model-visible agents in the first form that fits the limit:
  1. full `- name: description` lines;
  2. descriptions cut to 200 characters;
  3. names only;
  4. as many names as fit, plus "`N` more agents are not listed. See them with `list agents`."
  An empty catalog: "No agents are installed now."
- The schema pins `name` of `start agent` to the model-visible names at `make`, limited by the allowed names of the context.
- No `OperationDescribing` and no `ForkableTool` conformance.

## Acceptance Criteria
- [x] Each of the four forms and the empty form appear at the right limits.
- [x] The fixed sentences are present and complete in each form.
- [x] A `disable-model-invocation: true` agent is not in the description or the schema.
- [x] With the allowed names `a`, `b`, the schema and the description hold only `a` and `b`.
- [x] The schema holds the four operations and their parameters.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/AgentsToolDescriptionTests.swift` and `Tests/FoundationModelsAgentsTests/AgentsToolSchemaTests.swift`.
- [x] Run `swift test --filter "AgentsToolDescriptionTests|AgentsToolSchemaTests"`, then the guard tests. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.