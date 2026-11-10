---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m73by9tyqw8w51rk9rhm4bh1
  text: |-
    Discoveries:
    - Examples/agents-demo is not a separate package. It is the `agents-demo` executable target of the root Package.swift. Only the root and IntegrationTests/ have a Package.swift.
    - Package.resolved is in .gitignore (root and IntegrationTests). Thus the pin moves are local only, and the diff shows no Package.resolved change.
    - FoundationModelsSkills re-exports FoundationModelsExtras (`@_exported import` in SeamReexports.swift). Thus `.open` resolves in each file with `import FoundationModelsSkills`, and no file needs a new `import FoundationModelsExtras`.
    - `SkillsRegistry.onReload` is not optional in the new Skills. `try #require(skills.onReload)` in SkillsToolSharingTests gave a "redundant #require" warning. I changed it to `let reloads = skills.onReload`.
    - IntegrationTests had an old Extras pin (no ToolMode). `swift package update FoundationModelsExtras` alone gave Extras 3d0eced, which needs a newer mlx-swift-lm (MTPDrafterRegistration missing). A full `swift package update` in IntegrationTests corrected it. Root pins: Skills 9f07fb6, Extras 4254281. IntegrationTests pins: Skills b4e39c5, Extras 3d0eced.
    - No DocC article and no docs/ file has a code example that makes a SkillsRegistry. Only README.md has one.
    - `swift package edit --path` makes a `Packages/` symlink in the package folder and removes the pin from Package.resolved. `swift package unedit` removes both effects.
  timestamp: 2026-11-10T18:36:18.654661+00:00
- actor: claude-code
  id: 01m73bywvspec9yzf9kfmns8wr
  text: |-
    ### implement — changed
    - evidence: 11 files. Examples/agents-demo/DemoModes.swift, IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveProfile.swift, README.md, and in Tests/FoundationModelsAgentsTests: AgentEnvironmentTests, FindAgentsTests, MarketplaceEndToEndTests (3), ReadmeExampleSource, SkillsPreloadTests, SkillsToolSharingTests (6 calls, and the redundant #require of onReload), Support/AgentRunHarness, Support/SessionInstructionsFixture (2). 19 SkillsRegistry calls in total. No SkillsToolContext call. README and ReadmeExampleSource get one comment line for the mode.
    - No-default check: a scratch clone of Skills (b4e39c5) with `mode: ToolMode = .open` changed to `mode: ToolMode` in SkillsRegistry (4 inits) and SkillsToolContext.init, used through `swift package edit --path`. RED before the edits: "missing argument for parameter 'mode'" at DemoModes.swift. After the edits: root `swift build --build-tests` and IntegrationTests `swift build --build-tests` complete with no error. Then `swift package unedit` in both packages; no Packages/ folder and no scratch path is left.
    - Normal dependency: root `swift build --build-tests` complete, zero warnings in our code (only the mlx "missing creator" note). `swift test`: 913 tests in 119 suites passed. IntegrationTests `swift build`: complete.
    - next: /review
  timestamp: 2026-11-10T18:36:38.137467+00:00
- actor: claude-code
  id: 01m73c4tw89ge9k0av04yn1eqc
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (04aa733). 3 findings (3 confirmed, 1 refuted). Tests/FoundationModelsAgentsTests/FindAgentsTests.swift:140, Tests/FoundationModelsAgentsTests/SkillsToolSharingTests.swift:163, Tests/FoundationModelsAgentsTests/Support/SessionInstructionsFixture.swift:78 (all reuse/reuse: use AgentEnvironmentTests.makeEmptySkills() in place of the inline empty SkillsRegistry).
    - next: implement the 3 findings, then review again.
  timestamp: 2026-11-10T18:39:52.712166+00:00
- actor: claude-code
  id: 01m73c57hbwt8j4yhygs2dn5ja
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 11 files; 19 SkillsRegistry calls get mode: .open; no-default build check passed
    - test: green — root swift build --build-tests clean; swift test 913 passed in 119 suites; IntegrationTests build clean
    - commit: 04aa733
    - review: findings — Tests/FoundationModelsAgentsTests/FindAgentsTests.swift:140, Tests/FoundationModelsAgentsTests/SkillsToolSharingTests.swift:163, Tests/FoundationModelsAgentsTests/Support/SessionInstructionsFixture.swift:78
  timestamp: 2026-11-10T18:40:05.675862+00:00
- actor: claude-code
  id: 01m73c97n1qkq9gkwg96v20bfz
  text: |-
    Findings fix: I moved the empty-registry helper from `AgentEnvironmentTests.makeEmptySkills()` to the new Support file `Support/SkillsRegistry+Empty.swift` as `SkillsRegistry.makeEmpty()`. Reason: two Support files (AgentRunHarness, SessionInstructionsFixture) must use it, and a Support file must not depend on one test suite. The user permitted this move. Each caller now uses `SkillsRegistry.makeEmpty()`: AgentEnvironmentTests (7 calls), FindAgentsTests, SkillsToolSharingTests (the argument), the default of `skills` in Support/SessionInstructionsFixture.makeRunner, and the default of `skills` in Support/AgentRunHarness.make (one more inline empty registry that the search found). A search of Tests/ finds `SkillsRegistry(roots: [], mode: .open)` only in the helper. The demo and IntegrationTests are not in the test target, thus their inline registries stay.

    ### implement — changed
    - evidence: 6 files — Tests/FoundationModelsAgentsTests/Support/SkillsRegistry+Empty.swift (new), AgentEnvironmentTests.swift, FindAgentsTests.swift, SkillsToolSharingTests.swift, Support/AgentRunHarness.swift, Support/SessionInstructionsFixture.swift. `swift build --build-tests`: complete, zero warnings in our code (only the mlx "missing creator" note). `swift test`: 913 tests in 119 suites passed.
    - next: /review
  timestamp: 2026-11-10T18:42:16.865428+00:00
- actor: claude-code
  id: 01m73cdq9wv02pxk9xqpjs0htp
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (53c1bed): 0 findings, 0 confirmed, 0 refuted; 7 attempted, 0 failed. 6 files reviewed. All 3 prior Review Findings items are checked.
    - next: none. The task is in done.
  timestamp: 2026-11-10T18:44:43.964974+00:00
- actor: claude-code
  id: 01m73ce17qhepydqy5xp8k89g2
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — Support/SkillsRegistry+Empty.swift (new), AgentEnvironmentTests.swift, FindAgentsTests.swift, SkillsToolSharingTests.swift, Support/AgentRunHarness.swift, Support/SessionInstructionsFixture.swift
    - test: green — root swift build --build-tests clean; swift test 913 passed in 119 suites; IntegrationTests build clean
    - commit: 53c1bed
    - review: clean — 0 findings; 3 of 3 prior items checked; task moved to done
  timestamp: 2026-11-10T18:44:54.135003+00:00
position_column: done
position_ordinal: ff8f80
title: 'Give mode: explicitly at each SkillsRegistry init, for the required mode of FoundationModelsSkills (EXTRAS-12)'
---
## What
FoundationModelsSkills main (73ebb7a) added `mode: ToolMode` (FoundationModelsExtras `Sources/FoundationModelsExtras/Hosting/ToolMode.swift`, cases `.open` and `.sandboxed`) to the four public `SkillsRegistry` inits and to `SkillsToolContext.init`, with a temporary default `= .open`. Skills task `^na244z4` removes that default. This package must give `mode:` at each call first, or the build breaks.

- Run `swift package update FoundationModelsSkills` (and the dependencies it needs) so the local pin has 73ebb7a or later.
- Give `mode: .open` explicitly at each `SkillsRegistry(` call and each `SkillsToolContext(` call in `Sources/`, `Examples/agents-demo/`, `IntegrationTests/` and `Tests/FoundationModelsAgentsTests/`. Known calls: `Examples/agents-demo/DemoModes.swift`, `IntegrationTests/.../Support/LiveProfile.swift`, `AgentEnvironmentTests`, `FindAgentsTests`, `MarketplaceEndToEndTests` (3), `ReadmeExampleSource`, `SkillsPreloadTests`, `SkillsToolSharingTests` (6), `Support/AgentRunHarness.swift`, `Support/SessionInstructionsFixture.swift` (2). Find each call with a search; do not trust this list only. Tests, the demo and the integration tests run outside the App Sandbox, thus `.open` is correct.
- If a code example in `README.md` or a DocC article makes a `SkillsRegistry`, give `mode:` there too (`ReadmeExampleTests` compiles the README example).

## Acceptance Criteria
- [x] A search for `SkillsRegistry(` and `SkillsToolContext(` finds no call without `mode:` in the package, the demo or the integration tests.
- [x] The package builds against a FoundationModelsSkills with no default for `mode:` (check: remove the default in a local copy, or check each call by search).

## Tests
- [x] `swift build --build-tests` gives no error and no warning in our code. `swift test` passes.
- [x] `swift build` in `IntegrationTests/` and in `Examples/agents-demo/` (if they are separate packages) gives no error.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1

## Review Findings (2026-11-10 12:38)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 10 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file

- [x] `Tests/FoundationModelsAgentsTests/FindAgentsTests.swift:140` `reuse/reuse` — The new code writes SkillsRegistry(roots: [], mode: .open) inline. The test target already has a helper that makes this same empty registry. Writing it again means two copies of the empty-skills setup can drift apart. Replace the inline registry with `AgentEnvironmentTests.makeEmptySkills()`, as the test already does for `makeProfile()` on the same line.
- [x] `Tests/FoundationModelsAgentsTests/SkillsToolSharingTests.swift:163` `reuse/reuse` — The new argument `SkillsRegistry(roots: [], mode: .open)` duplicates the existing empty-registry helper. The test needs no skills, so the helper fits exactly. Pass `AgentEnvironmentTests.makeEmptySkills()` in place of the inline registry.
- [x] `Tests/FoundationModelsAgentsTests/Support/SessionInstructionsFixture.swift:78` `reuse/reuse` — The default argument for `skills` repeats the empty SkillsRegistry construction. The existing helper in the same test module already makes this value. Set the default to `AgentEnvironmentTests.makeEmptySkills()`.
