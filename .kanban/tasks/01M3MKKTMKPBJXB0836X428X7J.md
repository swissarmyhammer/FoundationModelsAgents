---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3n3bj8d5mddb7akgx07q4t7
  text: |-
    Research: `BackgroundToolRunner.start` (FoundationModelsExtras) calls `collectInstruction(forCompletionToken:)` and `canceler(forCompletionToken:)` of the tool before it gives the pending envelope, and only for a background call. `RunPlaneActor.start` always runs the body in a `Task`, thus the body of each background call always runs and ends. Thus the fix: `AgentsTool.canceler(forCompletionToken:)` opens the call in `StartedRuns`; `StartedRuns.add` or the end of `AgentsTool.call` closes it; `check agent` and `cancel agent` wait for an open call before they look up the run.

    RED: new `CheckAfterStartTests` (3 tests: check with token, check with no id, cancel with token, each in the pass after `start agent`). All 3 fail on the current code with the answers "No run has the id <token>. You have no runs." and "You have no runs.". The race is wide: even after `respond` returns, `runner.runs(caller:)` is empty. New scripted step `ScriptedAgentStep.toolCallWithLastToken(name:operation:)` reads the completion token from the last tool output.
  timestamp: 2026-09-28T22:49:48.557441+00:00
- actor: claude-code
  id: 01m3n3yys26tqb1jhz33cfdrmz
  text: |-
    Implementation landed (GREEN).
    - `StartedRuns`: new state `openCalls` (token -> waiting tasks). `open(call:)` records a call before its body runs. `add(_:forCall:)` ends the open call and resumes the waiters. New `close(call:)` ends a call whose body added no run, and drops its early cancel. New `waitForStart(ofCall:)` and `waitForStarts()`.
    - `AgentsTool.canceler(forCompletionToken:)` calls `open(call:)`: the Router asks for the canceler of each background call before it gives the envelope. `AgentsTool.call` closes the call of `ToolContext.current` in a `defer`, thus a corrective, a setup failure, or a payload that names no operation also ends the wait.
    - `AgentsToolContext.run(named:)` waits for the token before the lookup (`check agent` and `cancel agent` with an id). `reportsOfCallerRuns()` waits for all open calls (`check agent` with no id).
    - `checkWithNoIDListsOnlyRunsOfCaller` now calls `harness.tool.context.startedRuns.waitForStarts()` after the two `respond` calls, before it reads the runs.
    - Added a fourth test: `check agent` with the token of a `start agent` for an unknown agent gives the unknown-id corrective and does not wait for ever (this proves `close(call:)`).
    - Not changed (out of the scope of this card): `callerCannotCheckOrCancelRunOfOtherCaller`, `cancelRunsCancelsOnlyThatCaller` and `closeOfCallerCancelsOpenRun` read `runner.runs(caller:)` after the first gate arrival. The gate arrival comes from the driver, which `AgentRun.start` starts before `AgentRunner.start` puts the run in the index. Thus a very small race is still possible there. `waitForStarts()` is the tool to close it, if a person wants a card for it.
    - The five-times loop of `CheckAfterStartTests|AgentSchedulingTests` passed each time (15 tests).

    ### implement — changed
    - evidence: Sources/FoundationModelsAgents/Tool/StartedRuns.swift, Sources/FoundationModelsAgents/Tool/AgentsTool.swift, Sources/FoundationModelsAgents/Tool/AgentsToolContext.swift, Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift, Tests/FoundationModelsAgentsTests/CheckAfterStartTests.swift (new), Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift, Tests/FoundationModelsAgentsTests/Support/ScriptedAgentModel.swift, Tests/FoundationModelsAgentsTests/Support/ScriptedTranscriptText.swift; `swift test -Xswiftc -warnings-as-errors` 388 tests in 55 suites passed, 0 compiler warnings; `swiftlint lint Sources Tests Package.swift Examples` 0 violations; `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors` Build complete.
    - next: /review

    ```
    step: implement
    outcome: changed
    evidence: 8 files — StartedRuns.swift, AgentsTool.swift, AgentsToolContext.swift, AgentsToolOperations.swift, CheckAfterStartTests.swift (new), AgentSchedulingTests.swift, Support/ScriptedAgentModel.swift, Support/ScriptedTranscriptText.swift; swift test -Xswiftc -warnings-as-errors: 388 tests in 55 suites passed; swiftlint 0 violations; IntegrationTests build-tests complete
    task: ^x428x7j
    ```
  timestamp: 2026-09-28T23:00:23.970695+00:00
- actor: claude-code
  id: 01m3n47e7vm8khncrkv6dky9e2
  text: |-
    ### test — green
    - evidence: swift build -Xswiftc -warnings-as-errors — build complete, 0 errors; swift test -Xswiftc -warnings-as-errors — 388 tests, 55 suites, 0 failed; swiftlint lint Sources Tests Package.swift Examples — 0 violations, 0 serious, 133 files; cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors — build complete, 0 errors
    - next: none
  timestamp: 2026-09-28T23:05:01.947629+00:00
position_column: doing
position_ordinal: '80'
title: 'check agent and cancel agent right after start agent: the run can be absent before the start body adds it'
---
## Why
`start agent` is a background call with no `inlineSettleGrace` (^ggpyaem). The Router gives the pending envelope before the body of the call runs on the run plane. The body adds the run to the runner (`AgentRunner.startWithinLimit`) and to `StartedRuns` a short time later. A model that calls `check agent` or `cancel agent` at once, with the completion token or with no id, can get "No run has the id" or "You have no runs" for a run that starts some milliseconds later. The same gap makes some unit tests read `runner.runs(caller:)` too early; the tests now wait for a gate arrival or a `runSettled` event (see ^ggpyaem). `AgentSchedulingTests.checkWithNoIDListsOnlyRunsOfCaller` still reads the runs after the first gate arrival only.

## What
- Make `check agent` and `cancel agent` see a start call whose body did not add its run yet. For example: record the token of each background start call before the envelope goes back, and let `check agent` / `cancel agent` wait for the setup of that token (as `cancelRuns(caller:)` waits for `setups`).
- Make `checkWithNoIDListsOnlyRunsOfCaller` read the runs only after each start of the two callers added its run.

## Acceptance Criteria
- [x] A scripted test: a root session calls `start agent` and then `check agent` with the completion token in the next pass; the answer is the report of the run, never the unknown-id corrective.
- [x] `checkWithNoIDListsOnlyRunsOfCaller` has no race on the registration of the runs.

## Tests
- [x] `swift test -Xswiftc -warnings-as-errors` passes.