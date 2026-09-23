---
assignees:
- claude-code
depends_on:
- 01M376GQ5AB99BJYWHWW67DVCR
position_column: todo
position_ordinal: '8e80'
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
- [ ] Each of the four forms and the empty form appear at the right limits.
- [ ] The fixed sentences are present and complete in each form.
- [ ] A `disable-model-invocation: true` agent is not in the description or the schema.
- [ ] With the allowed names `a`, `b`, the schema and the description hold only `a` and `b`.
- [ ] The schema holds the four operations and their parameters.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentsToolDescriptionTests.swift` and `Tests/FoundationModelsAgentsTests/AgentsToolSchemaTests.swift`.
- [ ] Run `swift test --filter "AgentsToolDescriptionTests|AgentsToolSchemaTests"`, then the guard tests. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.