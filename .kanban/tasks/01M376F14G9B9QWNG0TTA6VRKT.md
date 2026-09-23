---
assignees:
- claude-code
depends_on:
- 01M376ER95A0C8N4KHFP9QS1JY
- 01M376DS6RBPHB0AEP6604D8Z7
position_column: todo
position_ordinal: '8780'
title: 'AgentRegistry: local layers, one-level read, AgentCatalog'
---
## What
Layer 2, local part (plan.md §4.1, §4.3 step 1, §12). No marketplace and no watcher in this task.

- `Sources/FoundationModelsAgents/Registry/AgentCatalog.swift`: `public struct AgentCatalog: Sendable` with `definitions`, `listing: [AgentListing]`, `diagnostics: [AgentDiagnostic]`, `definition(named:) -> AgentDefinition?`, `modelVisible`.
- `Sources/FoundationModelsAgents/Registry/AgentRegistry.swift`: `public final class AgentRegistry: Sendable` with `init(stack:variables:watch:)` and `init(layers:variables:watch:)` (the `SkillsRegistry` initializers). `catalog()` does no I/O and gives the cached catalog. `reload()` rebuilds and swaps it atomically (a `Mutex`).
- Build: a `FrontmatterDocumentStack(base: plain, decode: AgentFrontmatter.decode, onDiagnostic:)`; `plain.enumerate(MarketplaceLayer.agentsDirectoryName, suffix: ".md")` (one level); `documents.item(at: "agents/<id>.md")`; then `AgentDefinition.init`.
- The highest layer wins a path. Each lower copy gives an advisory on the winner's diagnostics.
- Each definition keeps its URL, its layer, and its layer index. The layer is kept for the render (§4.3 step 3).
- Keep `variables` on the registry for the render task.
- All file access goes through Extras; the guard tests must stay green.

## Acceptance Criteria
- [ ] The fixture stack gives the expected ids; the file name is the id.
- [ ] The user `code-reviewer.md` wins over the defaults copy, with one advisory.
- [ ] A `.md` file in a subfolder of `agents/` is not read.
- [ ] Each `broken/` file gives its diagnostic, and the good files next to it load.
- [ ] `catalog()` gives the same value with no I/O after the build (a second call after the files are deleted gives the same catalog until `reload()`).

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentRegistryTests.swift` covers each criterion.
- [ ] Run `swift test --filter AgentRegistryTests`, then the guard tests. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.