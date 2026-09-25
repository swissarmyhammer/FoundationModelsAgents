---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3dc2g7405gdwjznrds5rdsz
  text: |-
    Research and implementation notes.

    - `startWithinLimit` counts `openRuns` where `run.isWorking && run.id != callerID`. The caller id is `ToolContext.sessionID`, and a run session id is the run id. A root session is not in `openRuns`, thus the exclusion has an effect only when the caller is a run.
    - The doc comment of `startWithinLimit` states the same rule already. I did not change it.
    - plan.md §9.3 "The limit" and §16 (the list of unit tests) now state the rule. The DocC article `DelegatingWithTheAgentsTool.md` states it in the corrective list.
    - New test: `Tests/FoundationModelsAgentsTests/AgentSchedulingTests+CallingRun.swift`, suite "Agent scheduling: the calling run", nested in `AgentSchedulingTests` (the same pattern as `AgentSchedulingTests+Setup.swift`). A host-started lead run calls `start agent` and then waits on a gate in the same turn, thus it is working. With `maxConcurrentAgents: 1` its child starts. A host `start agent` at that time gets "2 agents are working now, and that is the limit. ...".
    - Why a separate file: when the case was in `AgentSchedulingTests.swift`, swiftlint reported `type_body_length` (262 of 250 lines), and the file was at the `file_length` limit of 400 lines. The case is in the `AgentSchedulingTests` suite, in its own extension file.
    - RED: I changed the count temporarily so that it also counts the calling run. Only the new test failed, at `#require(runner.runs(caller: parent.id).first)`: the parent got the limit corrective and no child started. I then restored the code. `git diff` shows no change in `Sources/.../Run/`.
    - A first mutation (`callerID != nil`) was wrong: it also changed the count of host calls and broke three other tests. Do not use it as a RED check.
  timestamp: 2026-09-25T22:48:13.284452+00:00
- actor: claude-code
  id: 01m3dc2j6vf52gqd5zffved1md
  text: |-
    ### implement — changed
    - evidence: 3 files — plan.md, Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md, Tests/FoundationModelsAgentsTests/AgentSchedulingTests+CallingRun.swift (new). `swift build -Xswiftc -warnings-as-errors`: complete. `swift test -Xswiftc -warnings-as-errors`: 357 tests in 49 suites pass. `cd IntegrationTests && swift build --build-tests`: complete. `swiftlint lint Sources Tests Package.swift Examples`: 0 violations.
    - next: /review
  timestamp: 2026-09-25T22:48:15.323768+00:00
- actor: claude-code
  id: 01m3dc9fzpc8e0465h3ydy36nv
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (4881fbe): 0 findings, 0 confirmed, 0 refuted. 1 file reviewed (Tests/FoundationModelsAgentsTests/AgentSchedulingTests+CallingRun.swift). No validator matches plan.md and DelegatingWithTheAgentsTool.md. The .reviewignore file excludes 4 .kanban files.
    - next: none. The task is in done.

    ```
    step: review
    outcome: clean
    evidence: 0 findings
    task: ^9geawdj
    ```
  timestamp: 2026-09-25T22:52:02.422914+00:00
- actor: claude-code
  id: 01m3dc9p9hxy0f09b1bnvza8d5
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files
    - test: green — swift test -Xswiftc -warnings-as-errors, 357 passed; swiftlint 0; IntegrationTests build --build-tests passes
    - commit: 4881fbe
    - review: clean — 0 findings
  timestamp: 2026-09-25T22:52:08.881276+00:00
depends_on:
- 01M3A6D0PH2N6Z6BWHGJ8KGEGV
- 01M3A6CQGZZC4VNCQM2Z6EPJ2M
position_column: done
position_ordinal: ab80
title: 'Decision B: state in the plan that the run limit does not count the calling run'
---
## Decision (recommended; confirm or change before /finish)
`AgentRunner.startWithinLimit` (`Sources/FoundationModelsAgents/Run/AgentRunner.swift`) does not count the run that calls `start agent`. This lets two sibling runs that wait for their children let those children start. Its doc comment already states the rule and the reason. Plan §9.3 says only that the limit "counts runs with a turn in operation". The recommendation: keep the behavior, write it into the plan and the DocC article, and prove it with a test.

## What
- plan.md §9.3 and the DocC article `DelegatingWithTheAgentsTool.md`: the limit counts the runs that are working, except the run that calls `start agent`. With `maxConcurrentAgents: 1`, a parent and one child can work together.
- Check that the doc comment of `startWithinLimit` says the same; change it only if it differs.

## Acceptance Criteria
- [x] The plan, the DocC article, and the doc comment state the same rule.
- [x] A test with `maxConcurrentAgents: 1` shows that a parent can start one child, and that a second start by a different caller at the same time gets the limit corrective.

## Tests
- [x] A case in `Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift`.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.