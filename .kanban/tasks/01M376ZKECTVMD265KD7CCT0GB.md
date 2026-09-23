---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m38a33944vkchy1bkw77j389
  text: 'Research: plan.md §2 has the table (header row "| Skills decision | Agents |"), §5 has the `skills:` preload, §6.1 and §6.2 have the marketplace layer and the partials rule. There is no `docs/` folder yet. The test helpers to use again are `PackageRoot.directory`, `SwiftSourceScan.holds(token:in:)`, and `DocumentationTests.speedWords` (it is private now; it becomes internal so that DocsTests uses the same list). No link parser exists in Tests; a new helper `Support/MarkdownLinks.swift` finds the relative links. Relative links in the document resolve from `docs/`.'
  timestamp: 2026-09-23T23:37:23.492217+00:00
- actor: claude-code
  id: 01m38aqmfjcx9616pgfman6ns3
  text: |-
    ### implement — changed
    - evidence: 5 files — docs/skills-and-agents.md (new), Tests/FoundationModelsAgentsTests/DocsTests.swift (new), Tests/FoundationModelsAgentsTests/Support/MarkdownLinks.swift (new), Tests/FoundationModelsAgentsTests/DocumentationTests.swift (speedWords is internal now), README.md (Documentation list links the new document). TDD: DocsTests was red with no document (16 issues), then green. `swift test --filter "DocsTests|DocumentationTests|ReadmeExampleTests"`: 19 tests in 3 suites passed. swiftlint: 0 violations.
    - next: test
  timestamp: 2026-09-23T23:48:36.466613+00:00
- actor: claude-code
  id: 01m38arkr4q1dcyp10qf1273qp
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 309 tests in 43 suites passed, 0 failed, 0 skipped; `swiftlint lint --quiet Sources Tests Examples` — 0 violations.
    - next: commit
  timestamp: 2026-09-23T23:49:08.484082+00:00
- actor: claude-code
  id: 01m38arvg6b9zt8d2kq8334t8j
  text: |-
    ### commit — changed
    - evidence: 3246e1c docs: skills-and-agents.md with the §2 table and DocsTests (the ^422kjy5 card files are not staged)
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T23:49:16.422273+00:00
- actor: claude-code
  id: 01m38ax21r8md5pt08yam7b3sm
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 0 confirmed, 0 refuted (7 attempted). No validator matches README.md or docs/skills-and-agents.md. The Swift files were reviewed.
    - next: done

    ### finish iteration 1 — clean
    - implement: changed — docs/skills-and-agents.md, DocsTests.swift, Support/MarkdownLinks.swift, DocumentationTests.swift (speedWords internal), README.md
    - test: green — 309 tests in 43 suites passed; swiftlint 0 violations
    - commit: changed — 3246e1c
    - review: clean — 0 findings
  timestamp: 2026-09-23T23:51:34.200834+00:00
depends_on:
- 01M376KBXZPH1WESVB084SCRS7
- 01M376JGKJAWX7DHWQC08C4GCH
position_column: done
position_ordinal: '9e80'
title: docs/skills-and-agents.md
---
## What
Plan.md §14 M8: a document on skills and agents. ASD-STE100 Simplified Technical English.

- Write `docs/skills-and-agents.md`: the §2 table (what transfers from Skills to agents), how one marketplace plugin gives `skills/` and `agents/`, and the partials rule. State that skills and agents are separate things: an agent uses skills through its `skills:` preload and the `skills` tool. To run a skill in its own context, a prompt tells an agent that has the `skills` tool to use the named skill.
- Add a test in `Tests/FoundationModelsAgentsTests/DocsTests.swift` that checks the file exists, holds the §2 table header row, and that each relative link in it resolves to a file in the repository.

## Acceptance Criteria
- [x] `docs/skills-and-agents.md` exists and holds the §2 table.
- [x] It states that skills and agents are separate, and how an agent uses a skill.
- [x] Each relative link in it resolves.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/DocsTests.swift`.
- [x] Run `swift test --filter DocsTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.