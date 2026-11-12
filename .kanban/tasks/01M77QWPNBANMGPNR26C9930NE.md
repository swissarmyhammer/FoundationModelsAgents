---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m77rhy6yksnbxqka5ncbr6te
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (0deca1d): 1 finding (1 confirmed, 0 refuted) — Tests/FoundationModelsAgentsTests/RunTemplateContextTests.swift:36 (reuse/reuse)
    - next: Remove the copy of `shellContext(enabled:)` from RunTemplateContextTests. Use one shared helper. Then review again.
  timestamp: 2026-11-12T11:33:42.750948+00:00
- actor: claude-code
  id: 01m77rkh2f6x21z8fz8gf60n00
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — AgentEnvironment.swift, AgentSessionMaker.swift, LoadingBoundaryTests.swift, AgentRunHarness.swift, RestoredRunFixture.swift, RunTemplateContextTests.swift, 3 DocC files
    - test: green — swift test, 963 tests in 127 suites; IntegrationTests build complete
    - commit: 0deca1d
    - review: findings — RunTemplateContextTests.swift:36
  timestamp: 2026-11-12T11:34:34.831060+00:00
- actor: claude-code
  id: 01m77rmwd669nx90m34g05d1g5
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (108f605): 0 findings, 0 confirmed, 0 refuted; 7 validator runs attempted, 0 failed; 3 files reviewed. The prior finding at RunTemplateContextTests.swift:36 is checked.
    - next: The task is in done.
  timestamp: 2026-11-12T11:35:19.206949+00:00
- actor: claude-code
  id: 01m77rn7wjtrhp46bghhh48dmg
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — ShellGroupFixture.swift, RunTemplateContextTests.swift, SessionAgentTemplateContextTests.swift
    - test: green — swift test, 963 tests in 127 suites
    - commit: 108f605
    - review: clean — 0 findings
  timestamp: 2026-11-12T11:35:30.962191+00:00
depends_on:
- 01M77QWFM3KKJJGA0C4AY9F28M
position_column: done
position_ordinal: ff9880
title: 'ACPA ^vshf002 (2): AgentEnvironment.make takes runTemplateContext, and the body of each run renders with the values of its resolved tools'
---
## What
Add the parameter `runTemplateContext: (@Sendable (AgentDefinition, [String]) -> [String: TemplateValue])? = nil` to `AgentEnvironment.make` and to the init of `AgentEnvironment` (Sources/FoundationModelsAgents/Run/AgentEnvironment.swift). Keep it as `public let runTemplateContext`.

In `AgentSessionMaker.resolveSetup(for:family:)` (Sources/FoundationModelsAgents/Run/AgentSessionMaker.swift), resolve the tools first. Then call `runTemplateContext` with the definition and the names of the resolved tools, and render the body of the run with the result (`AgentBodyRenderer.render(_:prompt:templateContext:)` from card (1)). A new run and a restored run both use `resolveSetup`, thus both get the values. A `nil` closure keeps the registry values. This card does not change the `skills:` preload or the `skills` tool: card (3) does that.

## Acceptance Criteria
- [x] A run of an agent with body `{% if tools.shell.enabled %}A{% else %}B{% endif %}` gets A when the closure gives `true`, and B when it gives `false`.
- [x] The closure gets the definition of the run and the names of its resolved tools.
- [x] A restored run gets the same values.
- [x] `nil` gives the instructions of today.

## Tests
- [x] Tests/FoundationModelsAgentsTests/RunTemplateContextTests.swift: the two branches for a new run, the tool names that the closure gets, a restored run, and `nil`.
- [x] `swift test` passes; IntegrationTests builds.

## Workflow
- Use `/tdd`. #step1

## Review Findings (2026-11-12 06:32)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 3 not reviewed.

> 3 file(s) not reviewed — no validator matched:
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/LoadingTheCatalog.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/RunningAnAgent.md` — no validator matches this file

- [x] `Tests/FoundationModelsAgentsTests/RunTemplateContextTests.swift:36` `reuse/reuse` — The new private helper `shellContext(enabled:)` repeats the helper of the same name in another test suite. The copy must change in two places if the shape of the shell group changes. Use one shared helper. Move the helper to a shared test support file, or make the existing `SessionAgentTemplateContextTests.shellContext` internal and call it from `RunTemplateContextTests`. Delete the local copy.
