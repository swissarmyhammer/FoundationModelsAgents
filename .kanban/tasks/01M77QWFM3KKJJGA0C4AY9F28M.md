---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m77r65sx64nsqbqswnyr1sy3
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (955e95e). 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed. 4 files reviewed. LoadingTheCatalog.md was not reviewed, because no validator matches it.
    - next: none. The task is in done.
  timestamp: 2026-11-12T11:27:17.309634+00:00
- actor: claude-code
  id: 01m77r6gjt1n827x6kg71h70aa
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — AgentBodyRenderer.swift, AgentRunner+DefaultAgent.swift, LoadingTheCatalog.md, LoadingBoundaryTests.swift, SessionAgentTemplateContextTests.swift
    - test: green — swift test, 955 tests in 126 suites; IntegrationTests build complete
    - commit: 955e95e
    - review: clean — 0 findings
  timestamp: 2026-11-12T11:27:28.346901+00:00
position_column: done
position_ordinal: ff9780
title: 'ACPA ^vshf002 (1): sessionAgentInstructions(for:templateContext:) renders the body with the given template context'
---
## What
FoundationModelsACPAgent ^vshf002 needs the values `tools.<group>.enabled` of a body to agree with the tool selection of the agent. Today `AgentBodyRenderer` (Sources/FoundationModelsAgents/Run/AgentBodyRenderer.swift) copies `registry.templateContext` at init, and each render uses it.

- `AgentBodyRenderer.render(_:prompt:templateContext:)`: the caller gives the template context. The narrowing `templateContext(_:of:)` (the `agents` group is off for an agent that denies it, 86dc3f8) applies to the given context too.
- Add `public nonisolated func sessionAgentInstructions(for definition: AgentDefinition, templateContext: [String: TemplateValue]) async throws(AgentRunFailure) -> SessionAgentInstructions` to `AgentRunner` (Sources/FoundationModelsAgents/Run/AgentRunner+DefaultAgent.swift). The body and its partials render with `templateContext` in place of the registry values. The layers, the variables and the `skills:` preload do not change.
- `sessionAgentInstructions(for:)` calls the new function with `registry.templateContext`. `defaultAgentInstructions()` does not change.
- Update the doc comments and LoadingTheCatalog.md.

## Acceptance Criteria
- [x] A body with `{% if tools.shell.enabled %}A{% else %}B{% endif %}` gives A for `tools.shell.enabled = true` and B for `false`, from the given context, and the registry context has no effect.
- [x] `for:` gives the same text as before (the registry values).
- [x] A partial of the body sees the given values.

## Tests
- [x] Tests/FoundationModelsAgentsTests/SessionAgentTemplateContextTests.swift: the two branches, a partial, and the `for:` default.
- [x] `swift test` passes.

## Workflow
- Use `/tdd`. #step1