---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mnav2c64e40wjcpkpec778
  text: |-
    External blockers (FoundationModelsExtras board), 2026-09-28:
    - OTel A ^65xmgkv (01M3MN838VZ4QX57C3965XMGKV): the API dependencies (swift-log, swift-metrics) in Extras.
    - OTel B ^z6jqd9g (01M3MN8N9P4RPET2V5JZ6JQD9G): the content-safety test helper, in a new `TelemetryTestSupport` product. The test of this task uses it.
    Remove the tag `waits-on-extras` when both are on Extras main.
  timestamp: 2026-09-28T18:44:44.748745+00:00
- actor: claude-code
  id: 01m3mtwbxeb0xwq7py2sfxj9s8
  text: |-
    2026-09-28 facts from swissarmyhammer-05 (Extras OTel A-D are done LOCALLY, not on Extras origin/main; do not start before they are pushed):
    - The tool span name is `FoundationModelsExtras.tool`; the Extras names are in `ExtrasTelemetry.swift`. `ToolCallSpan.withSpan` gives its body a `ToolCallSpan.Call` value, not a raw span.
    - `TelemetryCapture` (product `TelemetryTestSupport`) uses task-local `withTracer` and `withMetricsFactory`, and bootstraps logging only one time. A test process that uses it must NOT call `LoggingSystem.bootstrap` itself.
    - A logger or metric made before the first capture does not go to the capture. A `static let` logger or metric that a test touches before the capture starts is lost. Make loggers and metrics per call or per instance (or make sure the capture starts first).
    - `TracedCall.run` (the span plus the "enter" log helper) takes the trace id and span id from the `traceparent` that the tracer injects. `InMemoryTracer` does not inject, so its records have no ids; a test that checks the ids needs a tracer that injects.
  timestamp: 2026-09-28T20:21:41.934549+00:00
- actor: claude-code
  id: 01m3mv3scwgfs17x5z48rm3mzy
  text: '2026-09-28: Extras OTel A to D are on Extras origin/main (70ad74d). The `waits-on-extras` tag is removed. First step of this task: `swift package update FoundationModelsExtras` in the root and in `IntegrationTests/`, and record the resolved revision in a comment.'
  timestamp: 2026-09-28T20:25:45.116341+00:00
- actor: claude-code
  id: 01m3n8tdr91rc6fk4hyh61k3p6
  text: |-
    Picked up. Research results (2026-09-28):
    - `swift package update FoundationModelsExtras` ran in the root and in `IntegrationTests/`. Both resolve Extras at main 6c399a4. The Extras manifest declares the product `TelemetryTestSupport`. `Package.resolved` is in `.gitignore` in both places, thus no resolved file changes.
    - Versions to match: Extras uses swift-distributed-tracing from 1.4.1, swift-log from 1.15.1, swift-metrics from 2.11.0. Router uses swift-distributed-tracing from 1.4.1 only. No swift-otel.
    - `TelemetryCapture.run(forbidding:_:)` gives a `Context` (tracer `W3CInMemoryTracer`, `TestMetrics` factory, logger). It binds the tracer with `withTracer` and the factory with `withMetricsFactory`, and it bootstraps logging one time. It records one issue for each place that holds a forbidden string. `Context.spans`, `logRecords` and `metricRecords` tell what the capture measured.
    - Model: `RouterTracing.swift` (internal enum, nested `SpanName`, `AttributeKey`, value enums) and `ExtrasTelemetry.swift` (log label, `MetricName`, `LogMetadataKey` that reuses the attribute keys).
    - The fixture agent code-reviewer has `tools: Read, Grep`. A test can register `Read` in a `ToolCatalog`, thus the child can call a tool with a secret argument. `AgentRunHarness` has no tool catalog now; the test support gets one.
    - Periphery counts the test targets as callers, thus the vocabulary names have callers through the vocabulary tests until tasks ^wprxwv2, ^9q72162 and ^zqmx67z use them.
    - Decision: the card says each name has the prefix `FoundationModelsAgents.`. The span name, the attribute keys, the log metadata keys, the logger label and the metric names get the prefix. The outcome values and the failure kinds are values, not names, thus they are the plain words of the card (finished, failed, cancelled; hitMaxTurns, error, stopped). The failure kind gets its own attribute key, because a failed outcome carries a kind.
  timestamp: 2026-09-29T00:25:18.345372+00:00
- actor: claude-code
  id: 01m3n9bjd0cdjh4stpr2e7gvx4
  text: |-
    Implementation landed (TDD).
    - RED 1: the new tests did not compile, because the module `TelemetryTestSupport` was missing. RED 2: after the `Package.swift` change, they did not compile, because `AgentsTelemetry` was missing. GREEN after the vocabulary file.
    - Names: span `FoundationModelsAgents.run`; logger label `FoundationModelsAgents.runner` (the label cannot be the span name, because the vocabulary test requires distinct names); attribute keys and log metadata keys `FoundationModelsAgents.agent.name`, `.run.id`, `.run.parent_id`, `.caller.session_id`, `.run.depth`, `.run.outcome`, `.run.failure_kind`; metrics `FoundationModelsAgents.runs` and `FoundationModelsAgents.run.duration`; `Outcome` finished/failed/cancelled; `FailureKind` hitMaxTurns/error/stopped.
    - The vocabulary file imports no module. The three API products are declared in `commonDependencies`, thus the library, the example and the test target link them. No `swift-otel`.
    - Test support: `AgentRunHarness.make` takes a `tools: ToolCatalog` (default empty), thus the content-safety test registers the tool `Read` for the child code-reviewer.
    - DISCOVERY for ^wprxwv2, ^9q72162 and ^zqmx67z: in the content-safety test the capture holds only the Router spans `FoundationModelsRouter.resolve` and `FoundationModelsRouter.session`, 0 log records and 0 metrics. The submission spans of the sessions and the Extras tool spans, logs and metrics of the tool calls do not reach the capture, although the harness is made inside the capture. The Router pump and the tool calls run on tasks that do not inherit the task-local tracer and metrics factory. Thus a run span, log or metric that is emitted on the run task can also miss the capture. Each later task must make sure that its telemetry reaches the task-local capture (or passes the context explicitly), and must add its record to `expectMeasuredRuns` of `TelemetryContentSafetyTests`. Now that helper expects only non-empty spans.
  timestamp: 2026-09-29T00:34:40.160144+00:00
- actor: claude-code
  id: 01m3n9bsswk6rtc1hw7vbfsejy
  text: |-
    ### implement — changed
    - evidence: 5 files — Package.swift, Sources/FoundationModelsAgents/Telemetry/AgentsTelemetry.swift (new), Tests/FoundationModelsAgentsTests/AgentsTelemetryTests.swift (new), Tests/FoundationModelsAgentsTests/TelemetryContentSafetyTests.swift (new), Tests/FoundationModelsAgentsTests/Support/AgentRunHarness.swift. `swift test -Xswiftc -warnings-as-errors`: 397 tests in 58 suites passed, 0 warnings. `swift build -Xswiftc -warnings-as-errors`: complete. `swiftlint lint Sources Tests Package.swift Examples`: 0 violations in 137 files. `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors`: complete. Extras resolved at main 6c399a4 in both packages.
    - next: /review. Not committed.
  timestamp: 2026-09-29T00:34:47.740631+00:00
- actor: claude-code
  id: 01m3n9gx9fws9dme5jt3eq31cc
  text: '### test — green\n- evidence: `swift build -Xswiftc -warnings-as-errors` — build OK, 0 errors, 0 warnings from project code. `swift test -Xswiftc -warnings-as-errors` — 397 tests, 58 suites, 397 passed, 0 failed, 0 skipped. `swiftlint lint Sources Tests Package.swift Examples` — 0 violations, 0 serious, in 137 files. `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors` — build OK, 0 errors, 0 warnings from project code.\n- next: the task is clean and can move to review.'
  timestamp: 2026-09-29T00:37:35.151535+00:00
- actor: claude-code
  id: 01m3n9pjxtth5xy3hv6xakmd9t
  text: |-
    ### review — clean
    - evidence: 0 findings. The engine ran `review sha HEAD~1..HEAD` (commit 106cc17). It examined 5 files (7 attempts, 0 failed, 0 refuted). It did not examine 6 files in `.kanban/` because `.reviewignore` excludes them.
    - The task has no earlier `## Review Findings` sections. All acceptance criteria and test items have a check mark.
    - next: The task moved to done. The tasks OTel 2, OTel 3 and OTel 4 do not wait on this task now.
  timestamp: 2026-09-29T00:40:41.146814+00:00
- actor: claude-code
  id: 01m3n9psxq0e4z0tp4m8tka8zq
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files (Package.swift, AgentsTelemetry.swift, AgentsTelemetryTests.swift, TelemetryContentSafetyTests.swift, AgentRunHarness.swift); Extras resolved at 6c399a4
    - test: green — swift test -Xswiftc -warnings-as-errors, 397 tests in 58 suites passed; swiftlint 0; IntegrationTests build-tests complete
    - commit: 106cc17
    - review: clean — 0 findings
  timestamp: 2026-09-29T00:40:48.311658+00:00
position_column: done
position_ordinal: bc80
title: 'OTel 1: the AgentsTelemetry vocabulary file, the API dependencies, and the content-safety test'
---
## Why
The user approved the OpenTelemetry design on 2026-09-28 (the design file of the swissarmyhammer session: `otel-design.md`). A library uses only the APIs `swift-distributed-tracing` (`Tracing`), `swift-log` (`Logging`) and `swift-metrics` (`Metrics`). Only executables depend on `swift-otel`. Each package has one vocabulary file and one content-safety test.

BLOCKED outside this board: the content-safety test uses the shared test helper from FoundationModelsExtras, and Extras task "OTel A" (01M3MN838VZ4QX57C3965XMGKV) adds `swift-log` and `swift-metrics` to Extras. Remove the tag `waits-on-extras` when the helper is on Extras `main`.

## What
- `Package.swift`: add `swift-distributed-tracing`, `swift-log` and `swift-metrics` to the `FoundationModelsAgents` target as API products only (use the versions that FoundationModelsExtras and FoundationModelsRouter use). Add no `swift-otel` dependency. `agents-demo` is an example, not a product executable: it bootstraps nothing in this task.
- Create `Sources/FoundationModelsAgents/Telemetry/AgentsTelemetry.swift`, in the form of `FoundationModelsRouter/Sources/FoundationModelsRouter/Tracing/RouterTracing.swift`. It holds, each with the prefix `FoundationModelsAgents.`:
  - the span name `FoundationModelsAgents.run`;
  - the span attribute keys: agent name, run id, parent run id, caller session id, depth, outcome;
  - the log metadata keys (the same set) and the logger label;
  - the metric names: run count, run duration;
  - the outcome values: finished, failed (with the failure kind: hitMaxTurns, error, stopped), cancelled.
  - A doc comment on each name states that it carries no content.
- The no content rule: no prompt text, task text, response text, final message text, tool arguments or tool output in any span attribute, log message, log metadata value or metric dimension. Names, ids, counts, depths, outcomes and durations are safe.
- `Tests/FoundationModelsAgentsTests/TelemetryContentSafetyTests.swift`: use the Extras helper. Run a scripted parent and child with a secret word in the task text, the child's answer and a tool argument; assert that no span attribute, log record or metric dimension holds the secret word. (The test becomes useful as tasks 2, 3 and 4 add the telemetry; add it here with the vocabulary so each later task keeps it green.)

## Acceptance Criteria
- [x] `FoundationModelsAgents` builds with the three API products and without `swift-otel`.
- [x] `AgentsTelemetry.swift` holds every name that this package emits, each with the prefix.
- [x] The content-safety test uses the Extras helper and passes.

## Tests
- [x] `TelemetryContentSafetyTests.swift` (new).
- [x] Run `swift build -Xswiftc -warnings-as-errors` and `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #otel