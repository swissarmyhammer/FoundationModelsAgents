---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37j3an54a0tra3qf5sx4qfg
  text: |-
    Research:
    - `StenciledDotfolderStack.render(_:at:in:)` takes a `QuarantinedText`, a document path relative to the layer root, and a layer. The trust comes from `layer.source` (`.defaults` is trusted). Extras scopes the partials by itself from `base.layers` (a marketplace document sees its own layer plus the local layers). The renderer also builds the base stack from the scoped layers, as the card says.
    - `SpanBuilder` (Extras) builds the spans: `appendOriginal`, `appendQuarantined` (an empty value adds no span), `finish()`.
    - The untrusted render allows no filter (`TemplateEngine.untrustedAllowedFilters` is empty). The trust test uses `{{ "agent"|upper }}`.
    - The fixture marketplace has only `house-rules.md`, and `defaults` has the same name. The test of a marketplace-only partial uses a registry with the fixture marketplace provider and one temporary local layer with no `_partials/`.
    - The document path is `MarketplaceLayer.agentsDirectoryName + "/<id>.md"`.
  timestamp: 2026-09-23T16:38:05.221874+00:00
- actor: claude-code
  id: 01m37j73vkwr23ev5vk5pp2tn9
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsAgents/Run/AgentBodyRenderer.swift, Sources/FoundationModelsAgents/Run/AgentRunFailure.swift, Tests/FoundationModelsAgentsTests/AgentBodyRendererTests.swift. `swift test -Xswiftc -warnings-as-errors --filter AgentBodyRendererTests`: 8 tests pass. swiftlint: 0 violations.
    - note: the Stencil filter is `uppercase`, not `upper`. A trusted render with `upper` fails with "Unknown filter".
    - next: test
  timestamp: 2026-09-23T16:40:09.331608+00:00
- actor: claude-code
  id: 01m37j84mxysh2ds22j89yjrbg
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 148 tests in 18 suites pass, 0 failed, 0 skipped. `swiftlint lint --quiet Sources Tests Examples` — 0 violations. The only build note is the mlx-swift "missing creator" note.
    - next: commit
  timestamp: 2026-09-23T16:40:42.909558+00:00
depends_on:
- 01M376FFWD8GJDT7HAJJ96F118
position_column: doing
position_ordinal: '80'
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