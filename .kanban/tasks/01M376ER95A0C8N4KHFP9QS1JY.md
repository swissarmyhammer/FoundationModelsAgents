---
assignees:
- claude-code
depends_on:
- 01M376E8QEMNGGR1SDFQ60XBZJ
position_column: todo
position_ordinal: '8680'
title: 'AgentDefinition: validation, diagnostics, visibility'
---
## What
Layer 1, part 2 (plan.md §4.2, §4.3 step 2, §10). Make one validated definition from one located document.

- `Sources/FoundationModelsAgents/Definition/AgentDiagnostic.swift`: `public struct AgentDiagnostic` in the shape of `SkillDiagnostic`: `severity` (`advisory`, `warning`, `skip`), `agent: String?`, provenance (layer index, layer root, file URL, `MarketplaceProvenance?`), `message`.
- `Sources/FoundationModelsAgents/Definition/AgentDefinition.swift`: `public struct AgentDefinition: Sendable`. `init?(id:document:provenance:diagnostics:)` takes the file name (the id) and a `Located<FrontmatterDocument<AgentFrontmatter>>?`, and applies the rule table of §4.3:
  - No frontmatter, or no decode after the retry: skip.
  - File name not 1–64 of `[a-z0-9-]`, or a leading, trailing, or doubled hyphen: skip.
  - `name` absent or not equal to the file name: warning; the file name stays the id.
  - `description` absent or empty: warning; not model-visible. Longer than 1024: warning.
  - Tier 3 field, `background: false`, a decode note, an unknown key: advisory.
  - `model`: Layer 1 checks only that it is a non-empty string.
  - Properties: `id`, `description`, `body` (raw, not rendered), `model: String?`, `compactionPrompt: CompactionPrompt?`, `maxTurns: Int?`, `tools: [String]?`, `disallowedTools: [String]`, `skills`, `color`, `background`, unknown keys, `isModelVisible`, `isUserInvocable`, `url`, `layer`, `marketplace: MarketplaceProvenance?`.
- `Sources/FoundationModelsAgents/Definition/AgentListing.swift`: `public struct AgentListing` (id, description, model text, color, background, unknown keys, visibility, provenance).
- The unknown tool, unknown skill, and model-match warnings come in later tasks, because they need the tool catalog, the skills registry, and the profile.

## Acceptance Criteria
- [ ] Each rule of the table gives the stated severity, tested with `broken/` files and inline documents: `bad-name.md` warns; `Bad_Name.md` is skipped.
- [ ] `isModelVisible == description valid && disable-model-invocation != true`; `isUserInvocable == user-invocable != false`.
- [ ] A Claude file with `permissionMode`, `hooks`, and `model: sonnet` loads with advisories and no skip.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentDefinitionTests.swift`.
- [ ] Run `swift test --filter AgentDefinitionTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.