---
assignees:
- claude-code
depends_on:
- 01M376GGK2RB6A3XA1PSVRGW9K
position_column: todo
position_ordinal: 8d80
title: 'AgentRunner: start, the run index, catalog() with model warnings, retained records, stop()'
---
## What
The actor that owns each run (plan.md §8.1, §9.3), the host-driven part. No concurrency limit, no depth, no children in this task.

- Create `Sources/FoundationModelsAgents/Run/AgentRunner.swift`: `public actor AgentRunner` with `init(registry: AgentRegistry, environment: AgentEnvironment)`.
  - `start(_ name: String, prompt: String) throws -> AgentRun` (host-driven, `caller == nil`, depth 1, slot from `defaultSlot`). An unknown name throws `AgentRunnerError.unknownAgent(name:available:)`.
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