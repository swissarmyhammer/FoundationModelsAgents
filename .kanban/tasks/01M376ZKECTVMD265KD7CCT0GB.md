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
depends_on:
- 01M376KBXZPH1WESVB084SCRS7
- 01M376JGKJAWX7DHWQC08C4GCH
position_column: doing
position_ordinal: '8180'
title: docs/skills-and-agents.md
---
## What
Plan.md §14 M8: a document on skills and agents. ASD-STE100 Simplified Technical English.

- Write `docs/skills-and-agents.md`: the §2 table (what transfers from Skills to agents), how one marketplace plugin gives `skills/` and `agents/`, and the partials rule. State that skills and agents are separate things: an agent uses skills through its `skills:` preload and the `skills` tool. To run a skill in its own context, a prompt tells an agent that has the `skills` tool to use the named skill.
- Add a test in `Tests/FoundationModelsAgentsTests/DocsTests.swift` that checks the file exists, holds the §2 table header row, and that each relative link in it resolves to a file in the repository.

## Acceptance Criteria
- [ ] `docs/skills-and-agents.md` exists and holds the §2 table.
- [ ] It states that skills and agents are separate, and how an agent uses a skill.
- [ ] Each relative link in it resolves.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/DocsTests.swift`.
- [ ] Run `swift test --filter DocsTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.