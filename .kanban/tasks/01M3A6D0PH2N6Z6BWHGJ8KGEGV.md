---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3d34evxqmttpvsq2x77t891
  text: |-
    Research:
    - `AgentRunner.start(_ request:)` is the one internal path for the host `start` and `startWithinLimit`. The setup (`AgentRun.start`) awaits off the actor, thus a start in setup is not in `openRuns`.
    - Plan: a `setups` table (key, caller, waiters) that `start(_ request:)` fills before its first suspension. `cancelRuns(caller:)` and `stop()` cancel the open runs first, then wait for each matching setup to end, then cancel and await each open run of the target. `stop()` sets a stopped flag first; the host `start` throws `.stopped`, and `startWithinLimit` gives a new `LimitedStart.stopped`.
    - Setup gate for the tests: the `agentsTool` maker of `AgentRunRequest` is async. The fixture `lead` has `tools: Agent(...)`, thus its setup calls the maker. `ToolCatalog.Factory` is sync and cannot hold.
    - Sync signal in the tests: the caller also has a gated open run. The test awaits `finalState()` of that run, thus it knows that the cancel call took its snapshot before the test opens the setup gate.
    - `AgentSchedulingTests.swift` has 371 lines and file_length is 400. The new cases go in `AgentSchedulingTests+Setup.swift`, an extension of the same suite.
  timestamp: 2026-09-25T20:12:00.253439+00:00
- actor: claude-code
  id: 01m3d4s3gwahjxenban0tr5e16
  text: |-
    Implementation landed.
    - RED: before the change, "cancelRuns(caller:) waits for a start of that caller in setup" failed (the lead run was not in the index after the call), and "stop() waits for a start in setup" failed (state `.running`). The `stopped` tests failed at compile time: `AgentRunnerError` had no `stopped`.
    - `AgentRunner`: a `setups` table (key, caller, waiters). `start(_ request:)` adds the start before its first suspension. After the setup, it puts the run in the index and then resumes the waiters. `cancelRuns(where:)` takes a snapshot of the matching setups, cancels the open runs, waits for each setup (`endOfSetup`, a checked continuation), then cancels each matching run of the index and awaits its final state. `stop()` sets `isStopped` first. The host `start` throws `.stopped`. `startWithinLimit` gives `LimitedStart.stopped`, and `start agent` gives `AgentsToolText.stopped`. The CLI switch maps `.stopped` to that text.
    - The new scheduling cases are in `AgentSchedulingTests+Setup.swift`, an extension of the `AgentSchedulingTests` suite, because `AgentSchedulingTests.swift` has 371 lines and file_length is 400. The gate type is at file scope because of the nesting rule.
    - Docs: plan.md §9.3 and RunningAnAgent.md state the setup wait and the stopped refusal.

    ### implement — changed
    - evidence: 10 files. Sources: Run/AgentRunner.swift, Run/AgentRunnerError.swift, Tool/AgentsToolText.swift, Tool/AgentsToolOperations.swift, CLI/AgentsCLIOperations.swift, Commands/AgentRunner+SlashCommands.swift (doc), FoundationModelsAgents.docc/RunningAnAgent.md. Plan: plan.md. Tests: AgentSchedulingTests+Setup.swift (new, 4 cases), AgentsCLITests.swift (1 case). `swift build -Xswiftc -warnings-as-errors`: pass. `swift test -Xswiftc -warnings-as-errors`: 345 tests in 47 suites pass. `cd IntegrationTests && swift build --build-tests`: pass. swiftlint: 0 violations.
    - next: /review
  timestamp: 2026-09-25T20:40:45.340169+00:00
- actor: claude-code
  id: 01m3d51v2df3agk952snd4c1jk
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (ebce4b8). 0 findings (0 confirmed, 0 refuted; 7 validator runs attempted, 0 failed). 8 files reviewed. No validator matched plan.md and RunningAnAgent.md. .reviewignore excluded 4 .kanban files.
    - next: none. The task is in done.
  timestamp: 2026-09-25T20:45:31.597881+00:00
- actor: claude-code
  id: 01m3d52195zb9a6bcwzwda1y4a
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 10 files
    - test: green — swift test -Xswiftc -warnings-as-errors, 345 passed; swiftlint 0; IntegrationTests build --build-tests passes
    - commit: ebce4b8
    - review: clean — 0 findings
  timestamp: 2026-09-25T20:45:37.957119+00:00
depends_on:
- 01M3A6BZSVQR5RJ7TNBJ0Z9Y9Q
position_column: done
position_ordinal: a680
title: stop() and cancelRuns(caller:) also cancel runs that are in setup
---
## What
In `Sources/FoundationModelsAgents/Run/AgentRunner.swift`, `cancel(_:)` takes a snapshot of the open runs. A run whose setup is still in progress (the render, the skills preload, the tool makers) is not in the index yet, so it escapes the cancel. The host then closes its session, and the run later posts into the closed session. Also, `stop()` does not stop later starts.

- Keep a set of the starts in setup, with their caller.
- `cancelRuns(caller:)` and `stop()` **wait** until each start of that caller (or of all callers) that is in setup ends its setup. Then they cancel it and await its final state, as for the other runs, all before they return. Thus a cancelled run posts its final message before `cancelRuns` returns, and never into a session that the host closes after the call.
- After `stop()`, the runner refuses each new start: the host `start` throws a new `AgentRunnerError.stopped`, and `start agent` gives a corrective.
- `Sources/FoundationModelsAgents/CLI/AgentsCLIOperations.swift` has a `switch` over `AgentRunnerError`: add the new case there, with a text in `Tool/AgentsToolText.swift`.

## Acceptance Criteria
- [x] A start whose setup waits during `cancelRuns(caller:)` ends as cancelled, and its post comes before `cancelRuns(caller:)` returns.
- [x] After `stop()`, `runner.start` throws `stopped`, `start agent` gives the corrective, and the CLI start gives an error.
- [x] Runs of other callers are not affected by `cancelRuns(caller:)`.

## Tests
- [x] Cases in `Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift`. Hold the setup with a gated skills preload or tool maker.
- [x] A case in `AgentsCLITests.swift` for a start after `stop()`.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.