---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3exggs6dbbxedzmpmr0qbh8
  text: 'Search for a production caller of `AgentRunner.run(completionToken:)` and of `runIDsByCompletionToken`: the search covered Sources, Examples, Tests, and IntegrationTests. Result: there is no production caller. The only caller is `AgentRunnerTests.completionTokenFindsRun` (two calls). `Entry.completionToken` is used only to fill and trim that map. Other `completionToken` uses are not the index and stay: `AgentRunRequest.agentSpawn` (the sidecar lineage), `AgentRun+FinalMessage` (the correlation ID of the post), and tests that read `context.completionToken` from the Router journal. Decision: remove the method, the map, and the `Entry` wrapper (it holds only the run after the removal), update the test to find the run through `run(id:)` and `runs(caller:)`, and remove the token sentences from plan §9.2 and §9.3. The same sentence is also in the doc comment of `AgentsToolOperations` start and in `TheFinalMessage.md`; those also change, so that the documents match the code.'
  timestamp: 2026-09-26T13:12:12.838426+00:00
- actor: claude-code
  id: 01m3exqtcp3q17ahxkm4rd90w6
  text: |-
    Implementation done. Changes:
    - `AgentRunner.swift`: removed `run(completionToken:)`, `runIDsByCompletionToken`, and the private `Entry` struct. `openRuns` is now `[ULID: AgentRun]` and `records` is `[AgentRun]`. The behavior of `runs`, `run(id:)`, `runs(caller:)`, `startWithinLimit`, `cancelRuns`, and `retireEndedRuns` does not change.
    - `AgentRunnerTests.swift`: the test `completionTokenFindsRun` is now `toolStartedRunIsInIndex`. It finds the tool-started run through `run(id:)` and `runs(caller:)`, before and after the run finishes.
    - plan.md §9.2: removed the token-map sentence. §9.3 "The index": `token → run` is now `runs(caller:)`.
    - Same token-map sentence removed from the doc comment of `StartAgent.execute` (`AgentsToolOperations.swift`) and from `TheFinalMessage.md`, so that they match the code.
    TDD note: this is a removal with no new behavior. The updated test ran and passed before the removal (it guards the kept behavior), and it passed after the removal. There was no red step, because no new behavior was added.
    Process note: I changed three doc comments in the test file with `sed` in the shell by mistake; the repo rule says to use the files tool. The result is correct and lint is clean.
    Verification: `swift build -Xswiftc -warnings-as-errors` pass; `swift test -Xswiftc -warnings-as-errors` 359 tests in 49 suites pass; `swiftlint lint Sources Tests Package.swift Examples` 0 violations in 123 files; `cd IntegrationTests && swift build --build-tests` pass; `swift build --product agents-demo -Xswiftc -warnings-as-errors` pass. The SwiftPM "missing creator for mutated node ... mlx-swift_Cmlx.bundle" line is a build-system message, not a compiler warning; it is also present without this change.
  timestamp: 2026-09-26T13:16:12.054707+00:00
- actor: claude-code
  id: 01m3exqw4f1kngj1bq2q8ve55s
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsAgents/Run/AgentRunner.swift, Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift, Sources/FoundationModelsAgents/FoundationModelsAgents.docc/TheFinalMessage.md, Tests/FoundationModelsAgentsTests/AgentRunnerTests.swift, plan.md; swift test 359 tests in 49 suites pass; swiftlint 0 violations; IntegrationTests build --build-tests pass; agents-demo build pass
    - next: /review
  timestamp: 2026-09-26T13:16:13.839879+00:00
depends_on:
- 01M3A6D0PH2N6Z6BWHGJ8KGEGV
- 01M3A6DKKKADT8YYMXA9GEAWDJ
position_column: doing
position_ordinal: '80'
title: Remove the completion-token index that only tests use
---
## What
`AgentRunner.run(completionToken:)` and its token map (`Sources/FoundationModelsAgents/Run/AgentRunner.swift`) are used only by `AgentRunnerTests`. Plan §9.2 ("The runner index maps the `completionToken` of the call to the run") and §9.3 describe the index.

- Search the code for a production caller. If there is none, remove the method, the map, the two test calls in `AgentRunnerTests.swift`, and the sentences in plan §9.2 and §9.3.
- If a production caller needs it, keep it and add a test through that caller. Write the reason as a comment on this task.

## Acceptance Criteria
- [x] The token index is removed, or it has a production caller that a test covers.
- [x] Plan §9.2 and §9.3 match the code.

## Tests
- [x] Update `AgentRunnerTests.swift`.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.