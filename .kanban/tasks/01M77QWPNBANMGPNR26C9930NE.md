---
assignees:
- claude-code
depends_on:
- 01M77QWFM3KKJJGA0C4AY9F28M
position_column: todo
position_ordinal: '8180'
title: 'ACPA ^vshf002 (2): AgentEnvironment.make takes runTemplateContext, and the body of each run renders with the values of its resolved tools'
---
## What
Add the parameter `runTemplateContext: (@Sendable (AgentDefinition, [String]) -> [String: TemplateValue])? = nil` to `AgentEnvironment.make` and to the init of `AgentEnvironment` (Sources/FoundationModelsAgents/Run/AgentEnvironment.swift). Keep it as `public let runTemplateContext`.

In `AgentSessionMaker.resolveSetup(for:family:)` (Sources/FoundationModelsAgents/Run/AgentSessionMaker.swift), resolve the tools first. Then call `runTemplateContext` with the definition and the names of the resolved tools, and render the body of the run with the result (`AgentBodyRenderer.render(_:prompt:templateContext:)` from card (1)). A new run and a restored run both use `resolveSetup`, thus both get the values. A `nil` closure keeps the registry values. This card does not change the `skills:` preload or the `skills` tool: card (3) does that.

## Acceptance Criteria
- [ ] A run of an agent with body `{% if tools.shell.enabled %}A{% else %}B{% endif %}` gets A when the closure gives `true`, and B when it gives `false`.
- [ ] The closure gets the definition of the run and the names of its resolved tools.
- [ ] A restored run gets the same values.
- [ ] `nil` gives the instructions of today.

## Tests
- [ ] Tests/FoundationModelsAgentsTests/RunTemplateContextTests.swift: the two branches for a new run, the tool names that the closure gets, a restored run, and `nil`.
- [ ] `swift test` passes; IntegrationTests builds.

## Workflow
- Use `/tdd`. #step1