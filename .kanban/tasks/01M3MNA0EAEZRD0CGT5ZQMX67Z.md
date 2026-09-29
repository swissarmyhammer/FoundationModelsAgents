---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mtwh4aatmb7jxb6hn8m9xw
  text: '2026-09-28: use `TelemetryCapture` (Extras `TelemetryTestSupport`, task-local `withMetricsFactory`) in the tests. Make the metrics per run or per call, not a `static let`: a metric made before the first capture does not go to the capture. See the facts comment on ^96s67ks. This changes "a test metrics factory (injected)" in the Tests section to `TelemetryCapture`.'
  timestamp: 2026-09-28T20:21:47.274720+00:00
- actor: claude-code
  id: 01m3nd5gycmmh8s3128xhytg1c
  text: |-
    Picked up. Research results (2026-09-29):
    - swift-metrics 2.11.0 is resolved. `Counter(label:dimensions:factory:)` and `Timer(label:dimensions:factory:)` exist. `MetricsSystem.factory` gives the task-local factory of `withMetricsFactory`, or else the global factory. A detached task (the Router pump) has no task-local factory, thus a child run needs an explicit seam.
    - `TelemetryCapture.Context.metricsFactory` is a `TestMetrics` (`MetricsTestKit`). `TestMetrics` keeps one handler for each label and set of dimensions (the order of the dimensions does not matter), thus `expectCounter(label, dimensions)` and `expectTimer(label, dimensions)` find the metric of one agent and one outcome. The test target must link the `MetricsTestKit` product.
    - Plan: `AgentEnvironment.metricsFactory: (any MetricsFactory)?` (default `nil` = `MetricsSystem.factory` when the run ends). New file `Run/AgentRun+Metrics.swift`. `AgentRun.traced(in:_:)` already measures the duration of each run (setup failures too) and writes the end record; it records the metrics in the same place, after the end record. The counter and the timer are made for each run with `factory:`, never in a `static let`. No `MetricsSystem.bootstrap`.
    - Dimensions: agent name, outcome, and the failure kind for a failed run only. The dimension keys are the span attribute keys (`AgentsTelemetry.MetricDimension`, like `LogMetadataKey`). No run id, session id, parent id or depth.
    - Decision for `catalogNotLoaded`: ^9q72162 writes one failed record with the agent name and the kind `catalogNotLoaded`, and no duration, because no run exists. The metrics do the same: the counter increments one time with the agent name, outcome `failed` and failure kind `catalogNotLoaded`. No duration is recorded, because no run started and no run time exists.
  timestamp: 2026-09-29T01:41:16.364630+00:00
- actor: claude-code
  id: 01m3ndqz1zevhkvx5n4gwvxcjp
  text: |-
    Implementation landed (TDD).
    - RED 1: the new tests did not compile (`extra argument 'metricsFactory' in call`). RED 2 (after the seam, before the recording): 9 issues, each `.missingMetric(label: "FoundationModelsAgents.runs", ...)` or the two new metric expectations of the content-safety test. GREEN after `Run/AgentRun+Metrics.swift`. Mutation check: with `runMetricsFactory` that ignores the factory of the environment, "the metrics factory of the environment gets one count and one duration of a parent and of its child" and the content-safety test fail (the child metrics do not reach the capture). The seam was then put back.
    - Seam: `AgentEnvironment.metricsFactory: (any MetricsFactory)?` (default `nil`). `AgentEnvironment.runMetricsFactory` gives that factory, or `MetricsSystem.factory` at the time of the call. The `Counter` and the `Timer` are made for each run with `factory:`; no `static let`, no `MetricsSystem.bootstrap` in the library or the tests. Tests give `TelemetryCapture.Context.metricsFactory` (a `TestMetrics`) through `AgentRunHarness.make(metricsFactory:)`.
    - Recording: `AgentRun.traced(in:_:)` computes the duration one time and gives it to the end record and to `recordMetrics(of:after:in:)`. A setup failure also goes through `traced`, thus it counts with outcome `failed` and kind `setupFailed`, and it records its duration.
    - `catalogNotLoaded` decision (the same as the log record of ^9q72162): `AgentRunner.start(_:prompt:)` calls `countStartBeforeLoad(of:)` beside `logStartBeforeLoad(of:)`. The counter increments one time with the agent name, outcome `failed` and kind `catalogNotLoaded`. The timer records nothing, because no run started and no run time exists (the log record has no duration either).
    - Dimensions: `AgentsTelemetry.MetricDimension` (new) = the attribute keys of agent name, outcome and failure kind. The failure kind is present only for a failed run. `TestMetrics` finds a metric only by its full set of dimensions, thus the tests also prove that no other dimension (for example a run id) is present.
    - Tests: `AgentRunMetricsTests` (7 tests: finished, failed with kind `error`, cancelled, setup failure, start before load, no factory = `MetricsSystem.factory`, parent and child through the seam). `AgentsTelemetryTests` has one new test for the dimension keys. `TelemetryContentSafetyTests.expectMeasuredRuns` now requires one counter and one timer for each of the lead and the child.
    - `Package.swift`: the test target links `MetricsTestKit` (swift-metrics) for `TestMetrics`. `AgentRun.swift` is unchanged (382 lines).
  timestamp: 2026-09-29T01:51:20.639624+00:00
- actor: claude-code
  id: 01m3ndr3p1fen0mws49fyhrpss
  text: |-
    ### implement — changed
    - step: implement
    - outcome: changed
    - evidence: 10 files — Package.swift, Sources/FoundationModelsAgents/Run/AgentEnvironment.swift, Sources/FoundationModelsAgents/Run/AgentRun+Metrics.swift (new), Sources/FoundationModelsAgents/Run/AgentRun+Tracing.swift, Sources/FoundationModelsAgents/Run/AgentRunner.swift, Sources/FoundationModelsAgents/Telemetry/AgentsTelemetry.swift, Tests/FoundationModelsAgentsTests/AgentRunMetricsTests.swift (new), Tests/FoundationModelsAgentsTests/AgentsTelemetryTests.swift, Tests/FoundationModelsAgentsTests/Support/AgentRunHarness.swift, Tests/FoundationModelsAgentsTests/TelemetryContentSafetyTests.swift. `swift test -Xswiftc -warnings-as-errors`: 424 tests in 62 suites passed, 0 compiler warnings. `swiftlint lint Sources Tests Package.swift Examples`: 0 violations in 146 files. `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors`: Build complete.
    - task: ^zqmx67z
    - next: /review. Not committed. The task stays in doing.
  timestamp: 2026-09-29T01:51:25.377322+00:00
- actor: claude-code
  id: 01m3ndxg7c5e2gzj02yz5gkzv4
  text: |-
    ### test — green
    - evidence: `swift build -Xswiftc -warnings-as-errors` — build OK, 0 code warnings (only package-cache disk-I/O notices from SwiftPM, not our code). `swift test -Xswiftc -warnings-as-errors` — 424 tests in 62 suites, 424 pass, 0 fail, 0 skip. `swiftlint lint Sources Tests Package.swift Examples` — 0 violations in 146 files. `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors` — build OK, 0 code warnings.
    - next: none. The build is clean.
  timestamp: 2026-09-29T01:54:22.060334+00:00
depends_on:
- 01M3MN916AA5AE3QAWE96S67KS
position_column: doing
position_ordinal: '80'
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
- [x] Each ended run increments the counter one time and records one duration, with the agent name and outcome dimensions.
- [x] No dimension holds content or an unbounded value (the content-safety test of ^96s67ks covers the metrics).

## Tests
- [x] `Tests/FoundationModelsAgentsTests/AgentRunMetricsTests.swift` (new): a test metrics factory (injected, not a global bootstrap that other tests see) records a finished, a failed and a cancelled scripted run; assert the counts, the dimensions and one duration each.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #otel