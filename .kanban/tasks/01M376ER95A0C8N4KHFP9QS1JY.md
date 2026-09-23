---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37cncjrg1sjwn9q9fm5n6nr
  text: 'Research: SkillDiagnostic (Skills Validation/SkillDiagnostic.swift) has Severity {advisory, warning, skip}, a nested Provenance (rootIndex, root, marketplace), and message. Skills keeps an over-limit description as data (still model-visible), thus a description is valid when it is not empty. FrontmatterDocument gives metadata nil both for no frontmatter and for a decode failure, thus one skip rule covers both. DotfolderStack.Layer is not Equatable, thus AgentDefinition is not Equatable; AgentListing holds the provenance and not the layer, thus it can be Equatable. Plan: AgentDiagnostic.Provenance (layerIndex, layerRoot, url, marketplace); init?(id:document:provenance:diagnostics: inout).'
  timestamp: 2026-09-23T15:03:05.560548+00:00
- actor: claude-code
  id: 01m37cxsqhe5fvj5brx7z80nfw
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsAgents/Definition/{AgentDiagnostic,AgentDefinition,AgentDefinitionRules,AgentListing}.swift, Tests/FoundationModelsAgentsTests/{AgentDefinitionTests,AgentDefinitionRows}.swift, Tests/FoundationModelsAgentsTests/Support/AgentDefinitionAttempt.swift. `swift test -Xswiftc -warnings-as-errors`: 85 tests in 12 suites pass. swiftlint: 0 violations.
    - note: the first test file had 446 lines (file_length, type_body_length). The rows went to AgentDefinitionRows.swift and the builders went to Support/AgentDefinitionAttempt.swift.
    - next: test
  timestamp: 2026-09-23T15:07:41.169356+00:00
- actor: claude-code
  id: 01m37cxyvn6sc3se4gh6t1zs5t
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 85 tests in 12 suites passed, 0 failed, 0 skipped; `swiftlint lint --quiet Sources Tests Examples` — 0 violations; no disabled or skipped test in Tests/.
    - next: commit
  timestamp: 2026-09-23T15:07:46.421632+00:00
- actor: claude-code
  id: 01m37cy4tcc0bx1rgm33yxkkgj
  text: |-
    ### commit — changed
    - evidence: 5ec07c4 feat(definition): validate one agent file into AgentDefinition with diagnostics and visibility
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T15:07:52.524843+00:00
- actor: claude-code
  id: 01m37d35q99xaxyn0yea1b4myy
  text: |-
    ### review — findings
    - evidence: 2 findings — Sources/FoundationModelsAgents/Definition/AgentDefinitionRules.swift:38, Tests/FoundationModelsAgentsTests/Support/AgentDefinitionAttempt.swift:26 (code-hygiene/magic-numbers-swift)
    - next: implement

    ### finish iteration 1 — findings
    - implement: changed (7 files)
    - test: green (85 tests, 0 lint violations)
    - commit: changed (5ec07c4)
    - review: findings (2, magic-numbers-swift)
  timestamp: 2026-09-23T15:10:37.289600+00:00
depends_on:
- 01M376E8QEMNGGR1SDFQ60XBZJ
position_column: doing
position_ordinal: '80'
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

## Review Findings (2026-09-23 10:07)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Sources/FoundationModelsAgents/Definition/AgentDefinitionRules.swift:38` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Tests/FoundationModelsAgentsTests/Support/AgentDefinitionAttempt.swift:26` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
