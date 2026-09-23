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
- actor: claude-code
  id: 01m388wxvr3xwj0eyq5dd9z2jv
  text: |-
    ### commit — changed
    - evidence: d8d2cfc docs: DocC catalog, four articles, and DocumentationTests
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T23:16:32.760512+00:00
- actor: claude-code
  id: 01m38958b7y52vgce5y8yp6s9y
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD — 1 finding (1 confirmed, 0 refuted): Tests/FoundationModelsAgentsTests/Support/SwiftSourceScan.swift:169 swift/fluent-usage
    - next: implement (rename the `findingIn:` label)

    ### finish iteration 1 — findings
    - implement: changed (DocC catalog, DocumentationTests, DocCommentRule, SwiftSourceScan whole-file form)
    - test: green (298 tests in 41 suites, 0 failed; swiftlint 0)
    - commit: changed d8d2cfc
    - review: findings (1) SwiftSourceScan.swift:169 swift/fluent-usage
  timestamp: 2026-09-23T23:21:05.639342+00:00
- actor: claude-code
  id: 01m3895wbd095bpc2pcsbzeren
  text: |-
    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsAgentsTests/Support/SwiftSourceScan.swift (label `findingIn reportedNumbers:` renamed to `using rule:`; the per-line form now passes `using:` by name, so the overload is not ambiguous), Tests/FoundationModelsAgentsTests/DocumentationTests.swift (call site).
    - next: test
  timestamp: 2026-09-23T23:21:26.125015+00:00
- actor: claude-code
  id: 01m3897aratbj6bhvqa5pztrfd
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 298 tests in 41 suites passed, 0 failed, 0 skipped; swiftlint 0 violations.
    - next: commit
  timestamp: 2026-09-23T23:22:13.642282+00:00
- actor: claude-code
  id: 01m3897g38hcbd6gmvf734fdsb
  text: |-
    ### commit — changed
    - evidence: 0bcd5da test(docs): name the whole-file rule parameter of reportedLines 'using'
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T23:22:19.112324+00:00
- actor: claude-code
  id: 01m389a3ecrq8jzbf9g0w3qf5c
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — 0 findings (0 confirmed, 0 refuted); the prior finding SwiftSourceScan.swift:169 is fixed in 0bcd5da and checked.
    - next: done

    ### finish iteration 2 — clean
    - implement: changed (label `findingIn:` renamed to `using:`)
    - test: green (298 tests in 41 suites, 0 failed; swiftlint 0)
    - commit: changed 0bcd5da
    - review: clean (0 findings)
  timestamp: 2026-09-23T23:23:44.460250+00:00
depends_on:
- 01M376K1CKEEBTSGDM55GVBMC3
- 01M376KBXZPH1WESVB084SCRS7
- 01M376J35YTN5ZDS4GF89F9TAG
- 01M376JGKJAWX7DHWQC08C4GCH
position_column: done
position_ordinal: 9c80
title: 'Documentation: DocC catalog and doc comments'
---
## What
Plan.md §14 M8, the API documentation. All text in ASD-STE100 Simplified Technical English.

- Create `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/FoundationModelsAgents.md` (landing page) and articles for the catalog, a run, the `agents` tool, and the final message.
- Give each public symbol a doc comment.
- Create `Tests/FoundationModelsAgentsTests/DocumentationTests.swift` with one rule: the method of `../FoundationModelsSkills/Tests/FoundationModelsSkillsTests/DocumentationTests.swift`.

## Acceptance Criteria
- [x] `DocumentationTests` passes.
- [x] `DocumentationTests` fails when a public symbol loses its doc comment (a test on an in-memory source).
- [x] The DocC catalog has the landing page and the four articles.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/DocumentationTests.swift`.
- [x] Run `swift test --filter DocumentationTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-09-23 18:16)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 7 not reviewed.

- [x] `Tests/FoundationModelsAgentsTests/Support/SwiftSourceScan.swift:169` `swift/fluent-usage` — The parameter label `findingIn:` does not form a complete grammatical phrase at the call site. When read aloud, 'report lines in directory finding in [rule]' is incomplete—'finding in' lacks a complement to be grammatical. Rename the label to `reportedBy:` or `using:` to form a complete phrase: 'report lines in directory reported by [rule]' or 'report lines in directory using [rule]'.
