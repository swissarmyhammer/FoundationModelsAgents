---
assignees:
- claude-code
depends_on:
- 01M3A6BZSVQR5RJ7TNBJ0Z9Y9Q
position_column: todo
position_ordinal: '8680'
title: stop() and cancelRuns(caller:) also cancel runs that are in setup
---
## What
In `Sources/FoundationModelsAgents/Run/AgentRunner.swift`, `cancel(_:)` takes a snapshot of the open runs. A run whose setup is still in progress (the render, the skills preload, the tool makers) is not in the index yet, so it escapes the cancel. The host then closes its session, and the run later posts into the closed session. Also, `stop()` does not stop later starts.

- Keep a set of the starts in setup, with their caller.
- `cancelRuns(caller:)` and `stop()` **wait** until each start of that caller (or of all callers) that is in setup ends its setup. Then they cancel it and await its final state, as for the other runs, all before they return. Thus a cancelled run posts its final message before `cancelRuns` returns, and never into a session that the host closes after the call.
- After `stop()`, the runner refuses each new start: the host `start` throws a new `AgentRunnerError.stopped`, and `start agent` gives a corrective.
- `Sources/FoundationModelsAgents/CLI/AgentsCLIOperations.swift` has a `switch` over `AgentRunnerError`: add the new case there, with a text in `Tool/AgentsToolText.swift`.

## Acceptance Criteria
- [ ] A start whose setup waits during `cancelRuns(caller:)` ends as cancelled, and its post comes before `cancelRuns(caller:)` returns.
- [ ] After `stop()`, `runner.start` throws `stopped`, `start agent` gives the corrective, and the CLI start gives an error.
- [ ] Runs of other callers are not affected by `cancelRuns(caller:)`.

## Tests
- [ ] Cases in `Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift`. Hold the setup with a gated skills preload or tool maker.
- [ ] A case in `AgentsCLITests.swift` for a start after `stop()`.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.