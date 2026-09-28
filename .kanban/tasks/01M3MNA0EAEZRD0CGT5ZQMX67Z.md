---
assignees:
- claude-code
depends_on:
- 01M3MN916AA5AE3QAWE96S67KS
position_column: todo
position_ordinal: '9880'
title: 'OTel 4: swift-metrics for agent run count and duration by agent name and outcome'
---
## Why
Design of 2026-09-28 (item C and item 4): metrics use `swift-metrics` (`Metrics`) only. A metric dimension never carries content, and it must have a small, fixed set of values.

## What
- Metric names from `AgentsTelemetry` (task ^96s67ks):
  - a `Counter` of agent runs;
  - a `Timer` (or histogram) of run duration.
- Dimensions: agent name and outcome (finished, failed, cancelled). Do not add run id, session id or any other value with no limit as a dimension. The failure kind (hitMaxTurns, error, stopped) may be a dimension, because its set is fixed.
- Record both when the run records its final state (`Run/AgentRun.swift`). A run that fails in setup (no session) counts too, with outcome failed.
- Do not bootstrap `MetricsSystem` in the library.

## Acceptance Criteria
- [ ] Each ended run increments the counter one time and records one duration, with the agent name and outcome dimensions.
- [ ] No dimension holds content or an unbounded value (the content-safety test of ^96s67ks covers the metrics).

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentRunMetricsTests.swift` (new): a test metrics factory (injected, not a global bootstrap that other tests see) records a finished, a failed and a cancelled scripted run; assert the counts, the dimensions and one duration each.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #otel