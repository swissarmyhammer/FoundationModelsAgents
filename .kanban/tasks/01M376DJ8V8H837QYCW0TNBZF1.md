---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m378kdm2m4rh3e98w4s69pkt
  text: |-
    Research:
    - `FoundationModelsRouterTestSupport` has no public scripted backend or container. `MLXFoundationModelsSessionBackend` is internal in Router. Thus this task writes its own `LanguageModelSessionBackend` over a real `LanguageModelSession(model:tools:instructions:)`. The real session then runs the tool loop, and the scripted `LanguageModel` executor only emits tool calls and text.
    - `LoadedLLMContainer.makeSession(instructions:tools:)` has a default that DROPS the tools. The container must write all four factories.
    - `Router.init(cacheDir:recordingsDir:probe:metadataSource:loader:pool:)` is public. Use a fresh `ModelPool()` for each profile. A shared pool gives a later router the container of the first router for the same ModelRef, thus the script of a different test.
    - The stub machine and stub metadata copy the numbers of `EchoModel.swift` in FoundationModelsACPAgent (64 GiB RAM, a 10 MB safetensors file).
    - `RoutedSession.transcript` is `get async`.
  timestamp: 2026-09-23T13:52:06.786868+00:00
- actor: claude-code
  id: 01m3791enpvhmzp5pkannrb097
  text: |-
    ### implement — changed
    - evidence: 5 files — Tests/FoundationModelsAgentsTests/ScriptedProfileTests.swift, Support/ScriptedProfile.swift, Support/ScriptedAgentModel.swift, Support/ScriptedSessionBackend.swift, Support/ScriptedGate.swift. `swift build --build-tests`: 0 warnings. `swift test`: 8 tests in 2 suites pass (5 in ScriptedProfileTests).
    - API: `ScriptedProfile.make(script: ScriptedAgentScript, recordingsDir: URL? = nil) async throws -> (Router, LanguageModelProfile)`. `ScriptedAgentScript([ScriptedAgentPlay(key:steps:)])`; steps are `.toolCall(name:argumentsJSON:)`, `.finalText(_)`, `.wait(ScriptedGate)`. A play matches when the instructions or the first prompt CONTAIN its key; the first match wins. `script.prompts` gives each turn prompt one time. `ScriptedGate`: `wait()`, `open()`, `waitForArrival()`; a cancelled waiter throws `CancellationError`.
    - Pitfall: `ResponseStream` is not `Sendable`. Make the stream inside the relay task.
    - next: test
  timestamp: 2026-09-23T13:59:46.614263+00:00
- actor: claude-code
  id: 01m3795c9w0bvj2s23md04gjmq
  text: |-
    ### test — green
    - evidence: `swift build --build-tests -Xswiftc -warnings-as-errors` clean; `swift test` — 8 passed, 0 failed, 0 skipped; `swiftlint lint --quiet` — 0 violations. The first swiftlint run gave 7 warnings (line_length x2, trailing_comma x2, nesting x3). The fix: shorter lines, no trailing commas, and the executor moved to the top-level `ScriptedAgentExecutor`.
    - note: the repo has no `.swiftformat` config. Default swiftformat also flags committed files, and its `trailingCommas` rule contradicts swiftlint `trailing_comma`. Thus it is not a gate here.
    - next: commit
  timestamp: 2026-09-23T14:01:55.260950+00:00
- actor: claude-code
  id: 01m3795jndxy3z6ch5rhz8q18v
  text: |-
    ### commit — changed
    - evidence: 658462e test: add a scripted LanguageModelProfile test support with no real model
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T14:02:01.773391+00:00
- actor: claude-code
  id: 01m379a0ymwrwq0rjd10hpd4yx
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings (0 confirmed, 0 refuted); 5 files reviewed; 2 .kanban files excluded by .reviewignore.
    - next: none; task moved to done.
  timestamp: 2026-09-23T14:04:27.476067+00:00
- actor: claude-code
  id: 01m379a2v300c88kr8qnhxzvbr
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files (ScriptedProfileTests.swift, Support/ScriptedProfile.swift, Support/ScriptedAgentModel.swift, Support/ScriptedSessionBackend.swift, Support/ScriptedGate.swift)
    - test: green — 8 passed, 0 failed, 0 skipped; -warnings-as-errors build clean; swiftlint 0 violations
    - commit: 658462e
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-09-23T14:04:29.411300+00:00
depends_on:
- 01M376D9AJZB96ZHWEEXGW96QC
position_column: done
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
- [x] A test makes a profile, calls `profile.flash.makeSession(...)`, and a turn gives the scripted final text.
- [x] A scripted step calls a mounted tool, and the tool output is in the transcript.
- [x] A gated step blocks the turn until the test opens the gate.
- [x] The two slots have different `chosen.stringValue` values.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/ScriptedProfileTests.swift` covers each criterion above.
- [x] Run `swift test --filter ScriptedProfileTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.