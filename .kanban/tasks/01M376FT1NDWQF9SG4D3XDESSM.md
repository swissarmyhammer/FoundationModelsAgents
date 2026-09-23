---
assignees:
- claude-code
depends_on:
- 01M376FFWD8GJDT7HAJJ96F118
position_column: todo
position_ordinal: '8980'
title: 'Body render: $ARGUMENTS as a quarantined span, then Stencil at agents/<id>.md'
---
## What
The two render passes of plan.md §4.3 step 3.

- Create `Sources/FoundationModelsAgents/Run/AgentBodyRenderer.swift`: `func render(_ definition: AgentDefinition, prompt: String) throws -> String`.
  1. Split the raw body at each `$ARGUMENTS`. Build a `QuarantinedText` with the body parts as `.original` spans and the prompt as a `.quarantined` span at each place. A body with no `$ARGUMENTS` is one `.original` span.
  2. Call `StenciledDotfolderStack.render(_:at:in:)` with the document path `agents/<id>.md` and the winning layer of the definition, with the registry `variables`.
- The stack scope: a marketplace document renders over its own marketplace layer and the local layers; a local document renders over the local layers only. Build the `StenciledDotfolderStack` for each case from the layers that the registry keeps.
- Trust comes from the layer: `defaults` is trusted; each other layer is untrusted (Extras does this from the layer).
- A render error becomes `AgentRunFailure.bodyRenderFailed(String)`. Create `Sources/FoundationModelsAgents/Run/AgentRunFailure.swift` with this case now; the run task adds the other cases.

## Acceptance Criteria
- [ ] Each `$ARGUMENTS` in the body becomes the whole prompt.
- [ ] A prompt with `{{ project }}` or `{% include "x" %}` lands as text (plan.md §16: a quarantined span is never scanned).
- [ ] A body with no `$ARGUMENTS` renders unchanged except for its own template tags.
- [ ] An include of `house-rules.md` from `agents/` resolves to `<layer root>/_partials/` (plan.md §16); a copy in `agents/_partials/` wins over it.
- [ ] A local body that includes a partial that only a marketplace layer has fails with `bodyRenderFailed`.
- [ ] Trust: a `defaults` body with a construct above an untrusted limit of `TemplateEngine` renders; the same body in the `user` layer fails with `bodyRenderFailed`.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentBodyRendererTests.swift` covers each criterion, with the fixture library and the fixture marketplace provider.
- [ ] Run `swift test --filter AgentBodyRendererTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.