---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3838364643gfvn97qp8pka1
  text: |-
    Research:
    - The Skills demo does not call its demo functions from tests. SkillsDemoTests runs only the built binary. Its test target does not depend on skills-demo.
    - This task needs direct calls. SwiftPM lets a test target depend on an executable target and `@testable import` it (module `agents_demo`). SwiftPM renames the entry point, thus main.swift top-level code does not clash. This also makes `swift test` build the binary before the tests run.
    - A `file://` source that names a folder (not `.git`) is served by `MarketplaceStore` at init with no fetch. The layer root is `<folder>/<path>`, and the key is the alias. The store does no catalog flattening for a folder. Thus `--marketplace` uses two sources over `Examples/agent-library/marketplace`: path `plugins/code-tools` (alias code-tools) and path `plugins/docs-tools` (alias docs-tools). Each layer root holds `agents/*.md`.
    - `MarketplaceProvenance.displayText` gives the id (no URL, by design).
    - Watch mode takes `registry.onReload` before `load()`; the stream yields the load catalog too. Iteration ends when the task is cancelled.
  timestamp: 2026-09-23T21:37:47.204925+00:00
- actor: claude-code
  id: 01m383e14v6rfxxzygecxq83t9
  text: |-
    ### implement — changed
    - evidence: 6 files — Package.swift, Examples/agents-demo/main.swift, Examples/agents-demo/AgentsDemoMode.swift, Examples/agents-demo/AgentsDemoLibrary.swift, Examples/agents-demo/DemoModes.swift, Tests/FoundationModelsAgentsTests/AgentsDemoTests.swift. `swift test --filter 'AgentsDemoTests|NoStandardOutWriteTests|SwiftSourceScanTests'`: 19 tests pass. `agents-demo --marketplace` lists doc-writer (docs-tools) and security-reviewer (code-tools).
    - next: test
  timestamp: 2026-09-23T21:41:01.723303+00:00
- actor: claude-code
  id: 01m383exqffpkh71dxh3n8zzrs
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 275 tests in 37 suites passed, 0 failed, 0 skipped; `swiftlint lint --quiet Sources Tests Examples` — 0 violations.
    - next: commit
  timestamp: 2026-09-23T21:41:30.991060+00:00
- actor: claude-code
  id: 01m383f59nxp6cp2wep4ate31j
  text: |-
    ### commit — changed
    - evidence: 9c085e1 feat(demo): agents-demo --watch and --marketplace modes
    - next: review
  timestamp: 2026-09-23T21:41:38.741072+00:00
- actor: claude-code
  id: 01m383zame5k371v4n5hf9cxmk
  text: |-
    ### review — findings
    - evidence: 8 findings — Examples/agents-demo/AgentsDemoLibrary.swift:22, :31; Examples/agents-demo/main.swift:14, :17, :20, :25, :38; Tests/FoundationModelsAgentsTests/AgentsDemoTests.swift:129
    - next: implement (iteration 2)

    ### finish iteration 1 — findings
    - implement: changed (6 files)
    - test: green (275 tests, 0 failed, 0 skipped; swiftlint 0)
    - commit: changed (9c085e1)
    - review: findings (8)
  timestamp: 2026-09-23T21:50:28.494922+00:00
depends_on:
- 01M376D9AJZB96ZHWEEXGW96QC
- 01M376XK8GJY5DVQ66492JW7TT
position_column: review
position_ordinal: '80'
title: 'agents-demo: --watch and --marketplace'
---
## What
Plan.md §13, the demo modes that need no profile. There is no default CLI mode: the CLI needs a resolved profile. Look at `../FoundationModelsSkills/Examples/skills-demo/` and `SkillsDemoTests.swift` for the method.

- `Examples/agents-demo/main.swift`: parse the mode, build the stack over `Examples/agent-library`, and dispatch. With no mode, print the usage.
- `Examples/agents-demo/DemoModes.swift`: put the work of each mode in functions that take their dependencies (registry, an output closure), so tests call them with no process.
  - `--watch`: print one `AgentReloadReport` on each `onReload`.
  - `--marketplace`: use `Examples/agent-library/marketplace` as a `file://` source of a `MarketplaceStore`, and list the agents with provenance.

## Acceptance Criteria
- [ ] `swift run agents-demo` with no mode prints the usage and exits 0.
- [ ] The `--watch` function prints a report after a file in a temporary copy of the library changes.
- [ ] The `--marketplace` function lists `security-reviewer` and `doc-writer` with their marketplace provenance.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentsDemoTests.swift`: run the built binary with no mode, and call the `--watch` and `--marketplace` functions directly.
- [ ] Run `swift test --filter AgentsDemoTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-09-23 16:41)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [ ] `Examples/agents-demo/AgentsDemoLibrary.swift:22` `code-hygiene/dead-code-swift` — var.static `root` is unused.
- [ ] `Examples/agents-demo/AgentsDemoLibrary.swift:31` `code-hygiene/dead-code-swift` — var.static `cacheDirectory` is unused.
- [ ] `Examples/agents-demo/main.swift:14` `code-hygiene/dead-code-swift` — var.static `usageExitCode` is unused.
- [ ] `Examples/agents-demo/main.swift:17` `code-hygiene/dead-code-swift` — var.static `failureExitCode` is unused.
- [ ] `Examples/agents-demo/main.swift:20` `code-hygiene/dead-code-swift` — var.static `standardOutput` is unused.
- [ ] `Examples/agents-demo/main.swift:25` `code-hygiene/dead-code-swift` — function.method.static `run(arguments:)` is unused.
- [ ] `Examples/agents-demo/main.swift:38` `code-hygiene/dead-code-swift` — function.method.static `run(mode:)` is unused.
- [ ] `Tests/FoundationModelsAgentsTests/AgentsDemoTests.swift:129` `swift/fluent-usage` — Argument label `agentCount` should be `for` to form a grammatical phrase at the call site. Currently reads as awkward "report prefix agent count"; should read as "report prefix for [value]". Change function signature from `private static func reportPrefix(agentCount: Int) -> String` to `private static func reportPrefix(for agentCount: Int) -> String`, and update call sites accordingly.
