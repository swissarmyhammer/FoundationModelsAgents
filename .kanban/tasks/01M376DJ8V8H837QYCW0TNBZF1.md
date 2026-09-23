---
assignees:
- claude-code
depends_on:
- 01M376D9AJZB96ZHWEEXGW96QC
position_column: todo
position_ordinal: '8180'
title: 'Test support: a scripted LanguageModelProfile with no real model'
---
## What
`LanguageModelProfile.init` is `package` in `FoundationModelsRouter`, thus this package cannot make a profile directly. Hermetic run tests (plan.md §15) need a resolved profile with two slots and a scripted model. Make one through the public `Router.init(recordingsDir:recorder:…probe:metadataSource:loader:)` and `router.resolve(profile:reporting:)`, as `../FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Configuration/EchoModel.swift` and its `StubModelLoader` do.

- Create `Tests/FoundationModelsAgentsTests/Support/ScriptedProfile.swift`:
  - A `ModelLoader`, a `MachineProbe`, and a `MetadataSource` stub, so that `resolve` gives a profile with a `standard` and a `flash` slot of two different `ModelRef` values, with no download.
  - `ScriptedProfile.make(script:recordingsDir:) async throws -> (Router, LanguageModelProfile)`.
- Create `Tests/FoundationModelsAgentsTests/Support/ScriptedAgentModel.swift`: a `LanguageModel` (tool calling) that plays a script keyed by the session instructions or the first user prompt. Each step is a tool call (tool name and JSON arguments) or a final text. It can wait on an `AsyncSemaphore`-like gate, so that tests can hold a run in its turn. It records each prompt that it gets.
- Look at `../FoundationModelsRouter/Tests/FoundationModelsRouterTests/Helpers/ScriptedToolCallingModel.swift` for the shape. Do not use `@testable import`.

## Acceptance Criteria
- [ ] A test makes a profile, calls `profile.flash.makeSession(...)`, and a turn gives the scripted final text.
- [ ] A scripted step calls a mounted tool, and the tool output is in the transcript.
- [ ] A gated step blocks the turn until the test opens the gate.
- [ ] The two slots have different `chosen.stringValue` values.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/ScriptedProfileTests.swift` covers each criterion above.
- [ ] Run `swift test --filter ScriptedProfileTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.