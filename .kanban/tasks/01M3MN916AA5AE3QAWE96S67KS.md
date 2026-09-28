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
position_column: todo
position_ordinal: '9580'
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
- [ ] `FoundationModelsAgents` builds with the three API products and without `swift-otel`.
- [ ] `AgentsTelemetry.swift` holds every name that this package emits, each with the prefix.
- [ ] The content-safety test uses the Extras helper and passes.

## Tests
- [ ] `TelemetryContentSafetyTests.swift` (new).
- [ ] Run `swift build -Xswiftc -warnings-as-errors` and `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #otel