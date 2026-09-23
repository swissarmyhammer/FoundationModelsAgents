---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37khhqww96zhpvwd4ph7m0t
  text: |-
    Research done.
    - `AgentRun.start(AgentRunRequest, environment:, renderer:)` is internal and async, and it does not throw. Thus `runner.start(_:prompt:)` is `async throws(AgentRunnerError)`.
    - `AgentRun` holds `caller`, `slot`, and `depth`. The index keeps the run, and the completion token when the run has a `ToolContext`.
    - The registry needs `load()` before its catalog has agents. The runner init does no I/O. The runner reads `registry.catalog()` at each call. The host calls `registry.load()` before `start`. With an unloaded registry, `start` throws `unknownAgent` with no available names.
    - The runner moves each ended run to the records at the head of each index call (`start`, `runs`, `run(id:)`, `stop`). `run.state` changes before `result()` returns, thus the move is deterministic for tests.
    - `catalog()` adds `ModelMatch.match(...).warning` (inherited = `defaultSlot`) and `ToolResolver.diagnostics(of:catalog:hasAgentsTool: false)`. The runs of this runner get no `agents` tool yet.
  timestamp: 2026-09-23T17:03:19.804399+00:00
- actor: claude-code
  id: 01m37py0twcvkc51c49xjngnxe
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsAgents/Run/AgentRunner.swift (new), Sources/FoundationModelsAgents/Run/AgentRunnerError.swift (new), Sources/FoundationModelsAgents/Run/AgentRun.swift (internal `finalState()`; `result()` uses it), Tests/FoundationModelsAgentsTests/AgentRunnerTests.swift (new, 8 tests), Tests/FoundationModelsAgentsTests/Support/AgentRunHarness.swift (`environment(maxRetainedRuns:)`, `makeRunner(maxRetainedRuns:)`). `swift test --filter AgentRunnerTests`: 8 passed. swiftlint: 0.
    - Discovery: the Router generation gate is per model container and is not cancellable while a waiter waits. Two gated turns on ONE slot never both reach their gates, and `ScriptedGate.waitForArrival()` then waits for ever (the time limit cannot stop it). The stop test puts one run on `flash` (code-reviewer) and one on `standard` (test-writer).
    - Discovery: `swift test` startup on this host takes 60 to 100 s. A `timeout 60` kills it before any output. Use a longer timeout.
    - next: test
  timestamp: 2026-09-23T18:02:34.204593+00:00
- actor: claude-code
  id: 01m37pz4771eanq3cxc563k631
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 172 tests in 22 suites passed, 0 failed, 0 skipped, no warnings (the mlx-swift "missing creator" build note is not ours); `swiftlint lint --quiet Sources Tests Examples` — 0 violations.
    - next: commit
  timestamp: 2026-09-23T18:03:10.439974+00:00
depends_on:
- 01M376GGK2RB6A3XA1PSVRGW9K
position_column: doing
position_ordinal: '80'
title: 'AgentRunner: start, the run index, catalog() with model warnings, retained records, stop()'
---
## What
The actor that owns each run (plan.md §8.1, §9.3), the host-driven part. No concurrency limit, no depth, no children in this task.

- Create `Sources/FoundationModelsAgents/Run/AgentRunner.swift`: `public actor AgentRunner` with `init(registry: AgentRegistry, environment: AgentEnvironment)`. The init stores its inputs and does no I/O. The host calls `registry.load()` before the first `start`.
  - `start(_ name: String, prompt: String) async throws(AgentRunnerError) -> AgentRun` (host-driven, `caller == nil`, depth 1, slot from `defaultSlot`). It is `async`, because `AgentRun.start` is `async`. An unknown name throws `AgentRunnerError.unknownAgent(name:available:)`.
  - The index: `runs`, `run(id:)`, a map from completion token to run, and for each run its caller, slot, and depth.
  - Records of finished runs (id, name, state, final text). `maxRetainedRuns` removes the oldest record.
  - `catalog() -> AgentCatalog`: the registry catalog plus the `model` match warnings and the unknown tool warnings of `ToolResolver`.
  - `stop()`: cancel all runs and close all sessions.
- One runner holds one profile.

## Acceptance Criteria
- [ ] Two host-driven runs with `async let` finish independently with their own texts.
- [ ] `start` with an unknown name throws `unknownAgent` with the available names.
- [ ] `run(id:)` finds a running run and a finished record.
- [ ] With `maxRetainedRuns` 2, a third finished run removes the oldest record.
- [ ] `catalog()` has a warning for `unknown-model.md` and for an unknown tool name.
- [ ] `stop()` cancels two gated runs, and both reach `.cancelled`.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentRunnerTests.swift` with `ScriptedProfile` covers each criterion.
- [ ] Run `swift test --filter AgentRunnerTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.