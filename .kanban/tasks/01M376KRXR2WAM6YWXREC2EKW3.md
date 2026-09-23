---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m388sz514eq4txytn70s9na6
  text: |-
    Research and implementation notes:
    - Each public declaration and each enum case in Sources already had a `///` doc comment. The new rule confirms it.
    - New `Support/DocCommentRule.swift`: a walk from the top of a file. A `///` line sets "documented". Attribute lines (also a multi-line `@Operation(...)`) keep it. Any other line clears it. A public declaration (`public`/`open` in the leading words) or an enum case (`case <lowercase name>` with no `:` at the end) with no doc comment is reported.
    - `SwiftSourceScan` got `lineNumbers(of: [Bool])` and `reportedLines(inDirectory:findingIn:)` (a whole-file rule). The per-line form now calls the whole-file form.
    - DocC catalog `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/`: landing page and the articles LoadingTheCatalog, RunningAnAgent, DelegatingWithTheAgentsTool, TheFinalMessage.
    - `xcrun docc convert` with the symbol graph from `swift package dump-symbol-graph --minimum-access-level public` gives 0 diagnostics.
    - Trap: a case-insensitive search for "slow" matches "isLowercase". The speed-word rows use `SwiftSourceScan.holds(token:in:)` for full tokens.
  timestamp: 2026-09-23T23:14:55.777169+00:00
- actor: claude-code
  id: 01m388t1h9sd28s7bgnd8tevhn
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsAgents/FoundationModelsAgents.docc/{FoundationModelsAgents,LoadingTheCatalog,RunningAnAgent,DelegatingWithTheAgentsTool,TheFinalMessage}.md, Tests/FoundationModelsAgentsTests/DocumentationTests.swift, Tests/FoundationModelsAgentsTests/Support/DocCommentRule.swift, Tests/FoundationModelsAgentsTests/Support/SwiftSourceScan.swift. `swift test --filter DocumentationTests` passes (Documentation suite green).
    - next: test
  timestamp: 2026-09-23T23:14:58.217146+00:00
- actor: claude-code
  id: 01m388wmghv5ge8knfhhpwapr6
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 298 tests in 41 suites passed, 0 failed, 0 skipped (only the mlx-swift "missing creator" build-system note, which is not ours); `swiftlint lint --quiet Sources Tests Examples` — 0 violations.
    - next: commit
  timestamp: 2026-09-23T23:16:23.185455+00:00
depends_on:
- 01M376K1CKEEBTSGDM55GVBMC3
- 01M376KBXZPH1WESVB084SCRS7
- 01M376J35YTN5ZDS4GF89F9TAG
- 01M376JGKJAWX7DHWQC08C4GCH
position_column: doing
position_ordinal: '8180'
title: 'Documentation: DocC catalog and doc comments'
---
## What
Plan.md §14 M8, the API documentation. All text in ASD-STE100 Simplified Technical English.

- Create `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/FoundationModelsAgents.md` (landing page) and articles for the catalog, a run, the `agents` tool, and the final message.
- Give each public symbol a doc comment.
- Create `Tests/FoundationModelsAgentsTests/DocumentationTests.swift` with one rule: the method of `../FoundationModelsSkills/Tests/FoundationModelsSkillsTests/DocumentationTests.swift`.

## Acceptance Criteria
- [ ] `DocumentationTests` passes.
- [ ] `DocumentationTests` fails when a public symbol loses its doc comment (a test on an in-memory source).
- [ ] The DocC catalog has the landing page and the four articles.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/DocumentationTests.swift`.
- [ ] Run `swift test --filter DocumentationTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.