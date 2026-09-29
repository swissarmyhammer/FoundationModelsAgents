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
- actor: claude-code
  id: 01m3na1n1frhjhpwnz3h5snxfc
  text: |-
    Picked up. Research results (2026-09-29):
    - Cause of the capture gap of ^96s67ks (spans): the Router pump is a detached task. `RoutedSessionActorPump.swift`, `wakePump()`: `pumpTask = Task.detached { await self.runPump() }`. A detached task does not inherit the task-local tracer of `withTracer`, the task-local metrics factory, or the task-local log capture of `TelemetryCapture`. Each submission span, tool span, tool "enter" record and tool metric comes from the pump or from a task that the pump made, thus it misses the capture.
    - The Router has an explicit tracer seam: `Router(tracer:)` gives the tracer to each handle, each session (`RouterTracing.tracer(explicit:)`) and each tool mount (`MountSite.tracer`, used by `ToolCallSpan.withSpan`). A test that gives `context.tracer` to `Router(tracer:)` gets the submission spans and the tool spans in the capture. There is no such seam for logs and metrics: `TelemetryLogRouting.currentContext` is internal to `TelemetryTestSupport`, and a detached task has no value for it.
    - Our own code also detaches: `AgentRun.startDriver` uses `Task.detached` (on purpose: the driver must not inherit the `ToolContext` of the `start agent` call).
    - Parent of a submission span: `beginSubmission` uses `ServiceContext.current`, and `runFirstSubmission` binds `first?.serviceContext`, the context that `send(_:)` captured. Thus a run that sends its task prompt in the context of the run span gets its task submission (and its continuations) as children of the run span.
    - GAP (Router): a submission that only mail starts has no parent. `RoutedSessionActorPump.swift`: `mailDeliveryMessage` has `serviceContext: nil`, and `runFirstSubmission` binds `first?.serviceContext`, which is `nil` when `letters` is empty. Thus the delivery submission of a parent run (the answer to the final message of a child) is a root span, not a child of the run span. Needed from the Router: a session-level `ServiceContext` (for example a parameter of `makeSession` or a `RoutedSession` property that the owner sets) that a mail-only submission uses as its parent.
    - In the `start agent` body, `ServiceContext.current` is the context of the Extras tool span: `ToolCallSpan.withSpan` binds it, and `RunPlaneActor` and `ToolRun` start the body with `Task {}`, which inherits it.
    - The Extras names (`ExtrasTelemetry`) and the Router names (`RouterTracing`) are internal. The tests find the tool span from the trace (the parent of the child run span), not by name.
  timestamp: 2026-09-29T00:46:43.759410+00:00
- actor: claude-code
  id: 01m3nare0fy5r943q5j1p8rgcp
  text: |-
    Implementation landed (TDD).
    - RED: the new tests did not compile, because `AgentEnvironment(tracer:)` did not exist (`extra argument 'tracer' in call`). GREEN after the production change. Mutation check: with `ServiceContext.withValue(nil)` in place of the span context, "a child run span is a child of the start agent tool span" and "each submission span of a child session is a child of the child run span" fail (`submission.parentSpanID → nil`). The binding was then put back.
    - Seam: `AgentEnvironment.tracer: (any Tracer)?` (default `nil` = `InstrumentationSystem.tracer` when the run starts), like `Router(tracer:)`. Tests give `context.tracer` of `TelemetryCapture` to the Router (through `ScriptedProfile.make(tracer:)`) and to the environment (through `AgentRunHarness.make(tracer:)`). No process-global state: no `withTracer` dependency and no `LoggingSystem.bootstrap`.
    - Span: `AgentRun.traced(by:_:)` (new file `Run/AgentRun+Tracing.swift`) calls `TracedCall.run` with a logger made for each run. `startDriver` starts a task that is NOT detached (it inherits the `ServiceContext` of the caller, the tool span for a child, and the log capture of a host test), and in it the detached drive task binds the span context with `ServiceContext.withValue`, thus `send(_:)` captures it. The span ends after `end(in:)` records the final state. A run whose setup fails also gets one span and one "enter" record, in `AgentRun.start`.
    - The span covers the drive, not the setup: the run id is the session id, and the session exists only after the setup, thus the "enter" record cannot hold the run id before the setup. The Router `session` span of the setup is a sibling of the run span (both under the tool span), not a child.
    - Attributes: agent name, run id, parent run id (only when a run started the run: `request.parent != nil`), caller session id, depth (int), outcome, failure kind. A failed run records `AgentRunSpanFailure` (description = the kind raw value only) and the error status. Mapping: `hitMaxTurns` → hitMaxTurns, `mailDeliveryPaused` → stopped, each other failure → error.
    - `TelemetryContentSafetyTests.expectMeasuredRuns` now requires 2 run spans, a submission span, a span that holds the Read tool name (the tool span), and the "enter" record of the lead.
    - GAP 1 (Router, record for the Router session, ask via the user): a submission that only mail starts has no parent span. `.build/checkouts/FoundationModelsRouter/Sources/FoundationModelsRouter/Session/RoutedSessionActorPump.swift:99` (`mailDeliveryMessage` has `serviceContext: nil`) and `:364` (`runFirstSubmission` binds `first?.serviceContext`, which is `nil` when only mail starts the answer). Thus the delivery submission of a parent run (its answer to the final message of a child) is a root span, not a child of the run span. Needed: a session-level `ServiceContext` that the owner of a session can set (for example a `serviceContext` parameter of `makeSession`, or a `RoutedSession` property), which a mail-only submission uses as its parent. The acceptance criteria of this task do not need it: they name the submission spans of the child session, and a child without children has no mail-only submission.
    - GAP 2 (Router, not needed for this task): the pump is a detached task, `RoutedSessionActorPump.swift:124` (`pumpTask = Task.detached { await self.runPump() }`). Thus a task-local tracer, metrics factory or log capture does not reach a submission, a tool call or a run that a tool call starts. Spans reach a capture through the explicit tracer. Logs and metrics have no explicit seam: the "enter" record of a CHILD run is written, but it does not reach the log capture of a test (the host backend gets it, because it is global). The same holds for the Extras tool "enter" records and tool metrics. A Router change that keeps the task-local values of the caller (or an explicit logger/metrics seam) is needed for a test to capture them. OTel 3 (^9q72162) adds a host `Logger` seam, which can carry the child records.
  timestamp: 2026-09-29T00:59:10.223468+00:00
- actor: claude-code
  id: 01m3narq6xv6c1b0p11x3dn33c
  text: |-
    ### implement — changed
    - evidence: 9 files — Package.swift, Sources/FoundationModelsAgents/Run/AgentEnvironment.swift, Sources/FoundationModelsAgents/Run/AgentRun.swift, Sources/FoundationModelsAgents/Run/AgentRun+Tracing.swift (new), Tests/FoundationModelsAgentsTests/AgentRunTracingTests.swift (new), Tests/FoundationModelsAgentsTests/Support/CapturedTrace.swift (new), Tests/FoundationModelsAgentsTests/Support/AgentRunHarness.swift, Tests/FoundationModelsAgentsTests/Support/ScriptedProfile.swift, Tests/FoundationModelsAgentsTests/TelemetryContentSafetyTests.swift. `swift test -Xswiftc -warnings-as-errors`: 405 tests in 59 suites passed, 0 compiler warnings. `swiftlint lint Sources Tests Package.swift Examples`: 0 violations in 140 files. `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors`: Build complete. Router gap (mail-only submissions have no parent) recorded above; it does not block the acceptance criteria.
    - next: /review. Not committed.
  timestamp: 2026-09-29T00:59:19.645581+00:00
- actor: claude-code
  id: 01m3nb0bfj15kq3w37v256scpg
  text: |-
    ### test — green
    - evidence: `swift build -Xswiftc -warnings-as-errors` — build OK, 0 code warnings. `swift test -Xswiftc -warnings-as-errors` — 405 tests, 59 suites, all pass, 0 fail. `swiftlint lint Sources Tests Package.swift Examples` — 140 files, 0 violations. `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors` — build OK, 0 code warnings.
    - next: none. The work is ready for the next step.
  timestamp: 2026-09-29T01:03:29.778184+00:00
depends_on:
- 01M3MN916AA5AE3QAWE96S67KS
position_column: doing
position_ordinal: '80'
title: 'OTel 2: a span for each agent run, a child of the start agent tool span, and the parent of the Router spans of its session'
---
## Why
Design of 2026-09-28 (item A): one span for each sub-agent run, so a trace shows the tree of agents. The span is a child of the tool span that started it, and the Router spans of the sub-agent session (`FoundationModelsRouter.submission`, `.compact`, and the tool spans inside) are its children. Hang detection (design item 8): a span is exported only when it ends, so a run, which can suspend for a long time, also writes one "enter" log record when it starts, with the Extras helper.

## What
- Span `AgentsTelemetry.SpanName.run` (`FoundationModelsAgents.run`), kind `.internal`, opened when the run starts and ended when the run records its final state (`Run/AgentRun.swift`, `Run/AgentRun+Drive.swift`).
- Parent: the `ServiceContext` of the `start agent` call. `start agent` is a background operation (task ^ggpyaem): its body runs on its own task. Capture `ServiceContext.current` in the tool call (the tool span of the Extras tool hosting) and pass it to the run, so the run span is its child. A host `AgentRunner.start` call uses the host's current context (or top level).
- Children: the Router takes the parent of a submission span from the `ServiceContext` of the message (`SessionMessage.serviceContext`, captured at `send(_:)`). So the run calls `send(_:)` inside the run span's context (`ServiceContext.withValue` or `withSpan`), and every later mail-caused submission of the session is also a child: check how the Router parents mail submissions, and if it uses the context of the first message or none, record that on this task and ask the Router session (via the user) for a way to pass the run context to the session.
- Attributes (names from `AgentsTelemetry`, no content): agent name, run id, parent run id (if any), caller session id (if any), depth, outcome (finished, failed with kind, cancelled). Record an error on the span for a failed run with the failure kind only, not the message text if it can hold content.
- The "enter" log record at run start through the Extras helper (`TracedCall.run`), with the same ids.

## Acceptance Criteria
- [x] A run has one `FoundationModelsAgents.run` span with the attributes above and no content.
- [x] A child run's span is a child of the parent's `start agent` tool span; the child session's Router submission spans are children of the child run span (test with an in-memory tracer).
- [x] One "enter" log record is written when a run starts.
- [x] The content-safety test (task ^96s67ks) still passes with the span.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/AgentRunTracingTests.swift` (new): parent and child scripted runs; assert the span tree and the attributes with an in-memory `Tracer` bootstrapped for the test (no process-global state that other tests see; use the explicit-tracer seam if the Router has one, as `RouterTracing.tracer(explicit:)` does).
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #otel