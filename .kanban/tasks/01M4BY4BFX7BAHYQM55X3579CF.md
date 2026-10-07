---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4c8bay1rdk2mtk4jx2mxtaa
  text: |-
    Research done.
    - The run span is not stored on AgentRun. In a Router session the tool span of the call is the active span of `ServiceContext.current` (the child run span is a child of the tool span, see AgentRunTracingTests). Thus the span event goes on `tracer.activeSpan(identifiedBy: ServiceContext.current)`, with the tracer `environment.tracer ?? InstrumentationSystem.tracer`. A CLI call has no active span: it writes only the log record.
    - The logger is `environment.makeRunLogger()`, the same logger as the run records.
    - `send caller` knows no agent name of its own run. The session of the run has the id of the run, thus `runner.run(id: ToolContext.current?.sessionID)` gives the sending run.
    - Both operations go through `AgentsToolContext.messageCaller(_:)` for the caller path, thus the to_caller record goes there one time. SendAgent records the to_run path.
    - A blank message and an unknown id send no message: they give no record (the three outcome values are delivered, ended, no_caller).
    - TelemetryCapture checks span events too (TelemetryCaptureTests), thus the content-safety test reads the event attributes.
    - agents-demo prints lines for `runSettled`; `runMessage` gives no line now. The OperationEvent has `correlationID` (the completion token of the start call): the new line shows that token, not `detail`.
  timestamp: 2026-10-07T22:39:35.873772+00:00
- actor: claude-code
  id: 01m4c8wpp0h6exkvtq37bapy3x
  text: |-
    Implementation landed (TDD: each new test failed first for the right reason, then passed).
    - CLI: `SendAgentCommand` (`agents agent send --id --message`) reuses `SendAgent`; AgentsCLI doc lists five commands and states that `send caller` has no command (a host has no caller). The "four" wording changed only in the CLI files.
    - Telemetry vocabulary: `EventName.messageSent` = `FoundationModelsAgents.agent.message.sent`; keys `message.direction`, `message.outcome`, `message.length` (with the prefix); `agent.name` and `run.id` reuse the run keys; enums `MessageDirection` (to_run, to_caller) and `MessageOutcome` (delivered, ended, no_caller). `LogMessage.messageSent` is the event name.
    - New `Tool/AgentsToolContext+Telemetry.swift`: `AgentMessageRecord` and `AgentsToolContext.record(_:)`: one info log record through `environment.makeRunLogger()`, and one event on the active span of `ServiceContext.current` (tool span in a Router session; none in the CLI). The text is never recorded, only `message.count`.
    - `SendAgent` records to_run (delivered/ended). `messageCaller(_:)` records to_caller (delivered/no_caller), thus `send caller` and `send agent` with the caller id each give one record. The sender run of to_caller comes from `runner.run(id: ToolContext.current.sessionID)`.
    - Decision to note: a blank message and an unknown id send nothing and give no record, because the card has only three outcome values.
    - Test support: `HarnessTelemetry` param on `AgentsToolHarness.make`; `RootSessionEvent` and `AgentsToolArguments.sendCaller` moved to the shared AgentsToolScripting.swift (SendCallerTests now uses them, no private copy); `MessageExchange` support scenario (root <-> lead, both directions) shared by the tracing and content-safety tests; `CapturedTrace.messageEvents`, `CapturedLog.messageRecords`.
    - agents-demo: `runMessage` now prints `message from run: <correlationID>`; it never prints the message detail.
    - Extra test beyond the card: AgentRunLoggingTests covers the ended and no_caller outcomes.
  timestamp: 2026-10-07T22:49:04.960533+00:00
- actor: claude-code
  id: 01m4c8x37jmb6qbskpkfwmrsaa
  text: |-
    ### implement — changed
    - evidence: `swift test` — 470 tests in 66 suites passed, 0 failures. One build-system line `warning: missing creator for mutated node ... mlx-swift_Cmlx.bundle` comes from the mlx-swift dependency build, not from a source file of this package. Files: Sources/FoundationModelsAgents/CLI/AgentsCLI.swift, CLI/AgentsCLIOperations.swift, Telemetry/AgentsTelemetry.swift, Tool/AgentsToolContext.swift, Tool/AgentsToolContext+Telemetry.swift (new), Tool/AgentsToolOperations.swift, Examples/agents-demo/DemoModes.swift; tests AgentsCLITests, AgentRunTracingTests, TelemetryContentSafetyTests, AgentRunLoggingTests, AgentsTelemetryTests, AgentsDemoTests, SendCallerTests, Support/AgentsToolHarness.swift, Support/AgentsToolScripting.swift, Support/CapturedLog.swift, Support/CapturedTrace.swift, Support/MessageExchange.swift (new).
    - next: /review. Not committed. Task stays in doing.
  timestamp: 2026-10-07T22:49:17.810555+00:00
- actor: claude-code
  id: 01m4c94jp5bk03pj8nqgeyxs68
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (6c80e3d); 1 finding (1 confirmed, 0 refuted) — Tests/FoundationModelsAgentsTests/Support/MessageExchange.swift:54 (reuse/reuse). No finding was about the grant selection (^m6x4er6) or the "four operations" doc wording (^125tp66).
    - next: Move the shared harness sequence of MessageExchange.run and SendCallerTests.runWithMessage into one helper, then commit and review again.
  timestamp: 2026-10-07T22:53:23.013759+00:00
- actor: claude-code
  id: 01m4c94sdzbt0pe83fqv16j2rh
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 19 files
    - test: green — swift test, 470 passed in 66 suites; IntegrationTests build complete
    - commit: 6c80e3d
    - review: findings — Tests/FoundationModelsAgentsTests/Support/MessageExchange.swift:54
  timestamp: 2026-10-07T22:53:29.919767+00:00
- actor: claude-code
  id: 01m4c99xq5h4475spa1nk68bns
  text: |-
    Finding MessageExchange.swift:54 (reuse/reuse) is done.
    - New shared helper `AgentsToolHarness.withStartedRun(script:telemetry:rootKey:rootPrompt:setUp:body:)` in Support/AgentsToolScripting.swift. It makes the harness, makes the root session on the `flash` slot, calls `setUp`, makes the event iterator, sends the first prompt, waits for the open start calls, finds the one run (`NestedRunTests.onlyRun`), calls `body`, and then closes the root session (also when `body` throws) and deletes the harness.
    - `body` gets a `StartedRootRun` (harness, root, run, events) with `nextEvent()`, which does the `#require` on the next event. New typealias `RootSessionEvent.Iterator`.
    - Callers: `MessageExchange.run`, `SendCallerTests.runWithMessage`, and one more copy of the same sequence in `SendCallerTests.sendCallerWithABlankMessageIsCorrective`. A search of the test target for `RootSessionEvent.iterator` found no other copy. The other suites use `streamSessionEvents()` with different steps, thus they are not the same sequence.
    - Order change: the helper finds the run directly after the first prompt, before the body reads events. This is the pattern of AgentSchedulingTests and AgentsToolMountTests (waitForStarts directly after respond). `runner.runs(caller:)` keeps ended runs, thus the blank-message test also finds its ended run.
    - The rule dump file (754K characters, many languages) was too large to read in one call. I read the generic rules and the Swift, duplication, reuse and test-integrity sections.
  timestamp: 2026-10-07T22:56:18.149163+00:00
- actor: claude-code
  id: 01m4c9a00pfc47bgq0xw84ye1e
  text: |-
    ### implement — changed
    - evidence: `swift test` — 470 tests in 66 suites passed, 0 failures. The only warning is the build-system line `missing creator for mutated node ... mlx-swift_Cmlx.bundle` from the mlx-swift dependency. Files: Tests/FoundationModelsAgentsTests/Support/AgentsToolScripting.swift, Tests/FoundationModelsAgentsTests/Support/MessageExchange.swift, Tests/FoundationModelsAgentsTests/SendCallerTests.swift.
    - next: /review. Not committed. Task stays in doing.
  timestamp: 2026-10-07T22:56:20.502499+00:00
depends_on:
- 01M4BXV22HHY1EYE8XEVSV23GW
position_column: doing
position_ordinal: '80'
title: CLI and telemetry for send agent and send caller
---
## What
plan.md §9.4 has a parity rule: the CLI mirrors the operations of the tool. Each new operation must also get telemetry that does not record the message text.

Files:
- `Sources/FoundationModelsAgents/CLI/AgentsCLIOperations.swift` and `Sources/FoundationModelsAgents/CLI/AgentsCLI.swift`:
  - Add `agents agent send --id <id> --message <text>`. It calls `send agent` for a run of the host.
  - `send caller` has no CLI command, because a host has no caller. State this in the doc comment.
  - Change "the four operations" in these doc comments to the correct text.
- `Sources/FoundationModelsAgents/Telemetry/AgentsTelemetry.swift`: add a log record and a span event `agent.message.sent` with these attributes:
  - `direction` (`to_run` / `to_caller`);
  - `agent.name`;
  - `run.id`;
  - `outcome` (`delivered` / `ended` / `no_caller`);
  - the message length.
  It does not record the text.
- `Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift`: call the telemetry in `SendAgent` and `SendCaller`.

## Acceptance Criteria
- [x] `agents agent send` delivers to a running host-started run, and gives the `runEnded` error for an ended run.
- [x] Each `send agent` and `send caller` call gives one `agent.message.sent` record with the attributes above.
- [x] No log record, span attribute or metric label holds the message text.

## Tests
- [x] Add CLI tests next to the existing `AgentsCLI` tests: delivered and ended.
- [x] Add a case to `Tests/FoundationModelsAgentsTests/TelemetryContentSafetyTests.swift`: a message with a marker string does not appear in any captured record or span.
- [x] Add an attribute test to `Tests/FoundationModelsAgentsTests/AgentRunTracingTests.swift`.
- [x] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.

## Review Findings (2026-10-07 17:50)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 19 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsAgentsTests/Support/MessageExchange.swift:54` `reuse/reuse` — MessageExchange.run repeats the harness setup, root-session iterator, respond, waitForStarts, onlyRun, and close sequence of SendCallerTests.runWithMessage. The two helpers differ only in their scripts and in the setUp closure, so the second helper is a parallel copy of the first. Both should share one helper that takes the script and the root-session hook as parameters. Move the shared sequence into one internal helper, for example in AgentsToolHarness or AgentsToolScripting, that takes the script, the telemetry, and an optional setUp closure. Have runWithMessage and MessageExchange.run both call it, and keep only their per-test scripts and assertions in their own files.
