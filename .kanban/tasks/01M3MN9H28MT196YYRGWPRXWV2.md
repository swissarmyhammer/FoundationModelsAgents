---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mnawz4dtc5m8j7pq0dbnz3
  text: |-
    External blockers (FoundationModelsExtras board), 2026-09-28:
    - OTel C ^ykgz2aa (01M3MN91YK71YVJ9C7WYKGZ2AA): the "enter" log helper for hang detection.
    - Also OTel A ^65xmgkv and OTel B ^z6jqd9g through task ^96s67ks.
    Remove the tag `waits-on-extras` when ^ykgz2aa is on Extras main.
    Open: the tool span name may change from `FoundationModelsRouter.tool` to `FoundationModelsExtras.tool`; the user has not decided. Do not hard-code the tool span name in the tests: find the parent span from the trace, not by name, or take the name from the module that defines it.
  timestamp: 2026-09-28T18:44:46.692020+00:00
- actor: claude-code
  id: 01m3mtwdv9z1ec2grj4gad4gyv
  text: '2026-09-28: the tool span name is decided: `FoundationModelsExtras.tool` (names in Extras `ExtrasTelemetry.swift`). `ToolCallSpan.withSpan` gives its body a `ToolCallSpan.Call` value. The "enter" helper is `TracedCall.run`; it takes the trace id and span id from the injected `traceparent`, and `InMemoryTracer` does not inject, so an id check needs a tracer that injects. See the facts comment on ^96s67ks (capture, logger and metric lifetime).'
  timestamp: 2026-09-28T20:21:43.913075+00:00
- actor: claude-code
  id: 01m3mv3vt8cyv8t0wtbrf771dh
  text: '2026-09-28: Extras OTel A to D are on Extras origin/main (70ad74d), so the enter-log helper (Extras C, `TracedCall.run`) is available. The `waits-on-extras` tag is removed. One open part: a test that checks the trace id and span id on the "enter" record needs a tracer that injects W3C `traceparent`; Extras OTel E (^wts388b, a W3C-capable test tracer) is in progress and not pushed. If ^wts388b is not on Extras main when this task runs, test the span tree and the "enter" record without the id check, and write the missing id check on this task as open, not checked.'
  timestamp: 2026-09-28T20:25:47.592066+00:00
- actor: claude-code
  id: 01m3mwcca6tg6bxqj4c07pjv3s
  text: '2026-09-28: Extras OTel E (^wts388b) is on Extras origin/main (6c399a4). `TelemetryCapture.Context.tracer` is now a `W3CInMemoryTracer`, and "enter" records of `TracedCall.run` in a capture have `trace.id` and `span.id`. So the id check is no longer open: do it. Code that needs the `InMemoryTracer` type uses `context.tracer.inMemoryTracer`; code that uses it as `any Tracer` or reads `finishedSpans` compiles as before. Run `swift package update FoundationModelsExtras` to get 6c399a4 or later.'
  timestamp: 2026-09-28T20:47:55.206484+00:00
- actor: claude-code
  id: 01m3n9bpkgm0gfhny4yavkcdxw
  text: '2026-09-29 fact from ^96s67ks: in `TelemetryContentSafetyTests` (harness made inside `TelemetryCapture.run`), the capture holds only `FoundationModelsRouter.resolve` and `FoundationModelsRouter.session`. No submission span and no Extras tool span, log or metric reaches it. The Router pump and the tool calls run on tasks that do not inherit the task-local tracer. Make sure that the run span reaches the capture (task-local inheritance or an explicit tracer), and add the run span to `expectMeasuredRuns` of `TelemetryContentSafetyTests`.'
  timestamp: 2026-09-29T00:34:44.464712+00:00
depends_on:
- 01M3MN916AA5AE3QAWE96S67KS
position_column: todo
position_ordinal: '9680'
title: 'OTel 2: a span for each agent run, a child of the start agent tool span, and the parent of the Router spans of its session'
---
## Why
Design of 2026-09-28 (item A): one span for each sub-agent run, so a trace shows the tree of agents. The span is a child of the tool span that started it, and the Router spans of the sub-agent session (`FoundationModelsRouter.submission`, `.compact`, and the tool spans inside) are its children. Hang detection (design item 8): a span is exported only when it ends, so a run, which can suspend for a long time, also writes one "enter" log record when it starts, with the Extras helper.

BLOCKED outside this board: the "enter" log helper comes from FoundationModelsExtras. Remove the tag `waits-on-extras` when it is on Extras `main`.

## What
- Span `AgentsTelemetry.SpanName.run` (`FoundationModelsAgents.run`), kind `.internal`, opened when the run starts and ended when the run records its final state (`Run/AgentRun.swift`, `Run/AgentRun+Drive.swift`).
- Parent: the `ServiceContext` of the `start agent` call. `start agent` is a background operation (task ^ggpyaem): its body runs on its own task. Capture `ServiceContext.current` in the tool call (the tool span of the Extras tool hosting) and pass it to the run, so the run span is its child. A host `AgentRunner.start` call uses the host's current context (or top level).
- Children: the Router takes the parent of a submission span from the `ServiceContext` of the message (`SessionMessage.serviceContext`, captured at `send(_:)`). So the run calls `send(_:)` inside the run span's context (`ServiceContext.withValue` or `withSpan`), and every later mail-caused submission of the session is also a child: check how the Router parents mail submissions, and if it uses the context of the first message or none, record that on this task and ask the Router session (via the user) for a way to pass the run context to the session.
- Attributes (names from `AgentsTelemetry`, no content): agent name, run id, parent run id (if any), caller session id (if any), depth, outcome (finished, failed with kind, cancelled). Record an error on the span for a failed run with the failure kind only, not the message text if it can hold content.
- The "enter" log record at run start through the Extras helper, with the same ids.

## Acceptance Criteria
- [ ] A run has one `FoundationModelsAgents.run` span with the attributes above and no content.
- [ ] A child run's span is a child of the parent's `start agent` tool span; the child session's Router submission spans are children of the child run span (test with an in-memory tracer).
- [ ] One "enter" log record is written when a run starts.
- [ ] The content-safety test (task ^96s67ks) still passes with the span.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentRunTracingTests.swift` (new): parent and child scripted runs; assert the span tree and the attributes with an in-memory `Tracer` bootstrapped for the test (no process-global state that other tests see; use the explicit-tracer seam if the Router has one, as `RouterTracing.tracer(explicit:)` does).
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #otel