---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3cwjn6z50egkkn2j8c5k45c
  text: |-
    Discoveries and work:
    - `finalMessage(for:)` now uses `report(of: state)` as the `detail` for each terminal state. The finished detail is "Agent `name` (`id`) finished.", a blank line, and the full text. The failed and cancelled details did not change. Thus the post and `check agent` give the same text from one source.
    - The `.alreadySettled` answer of `cancel agent` is now "The run ended before the cancel.", a blank line, and the detail of the final message. The detail names the agent, thus the answer names it one time. The old text named the agent two times also for a cancelled run.
    - The Router does not cut a `.completed` detail at `ToolContext.terminalDetailTailLimit`. The long-text test (6 900 characters) passes with the heading.
    - RED: 9 issues in FinalMessageTests, NestedRunTests, ReadmeExampleTests, AgentsToolOperationsTests, and AgentRunTests+Lineage before the change. GREEN after it.
    - New tests: `cancelFinishedRunNamesAgentOneTime` in AgentsToolOperationsTests. `leadJoinsBothResults` in NestedRunTests now checks that the prompts hold "Agent `name` (`id`) finished." with the text of each child, one time each. ReadmeExampleTests checks the heading with a pattern, because the example does not give the child id.
    - The live tests FullCircleTests and LiveNestedTests compared `detail` with the bare text. They now compare it with the named detail. The IntegrationTests package builds with `--build-tests`. I did not run the live suite, because it needs real models.
    - The agents-demo `--fan-out` mode prints `settled: ` plus the detail. It now shows the heading line too. AgentsDemoTests checks only the prefix, and it passes.
    - plan.md: §9.1 `check agent` row now gives the progress lines of ^j0z9y9q (Phase, Passes, Last tools, Text so far). The `cancel agent` row gives both answers. §9.2 gives the finished detail. The §15 unit test list names the new checks.
  timestamp: 2026-09-25T18:17:25.471483+00:00
- actor: claude-code
  id: 01m3cwjr7jw45ww0nswazyfdqe
  text: |-
    ### implement — changed
    - evidence: 12 files — Sources/FoundationModelsAgents/Run/AgentRun+FinalMessage.swift, Sources/FoundationModelsAgents/Tool/AgentsToolText.swift, Sources/FoundationModelsAgents/FoundationModelsAgents.docc/TheFinalMessage.md, README.md, plan.md, Tests/FoundationModelsAgentsTests/{FinalMessageTests,NestedRunTests,ReadmeExampleTests,AgentsToolOperationsTests,AgentRunTests+Lineage}.swift, IntegrationTests/Tests/AgentsIntegrationTests/{FullCircleTests,LiveNestedTests}.swift. `swift build -Xswiftc -warnings-as-errors`: complete. `swift test -Xswiftc -warnings-as-errors`: 332 tests in 45 suites passed. `swiftlint lint Sources Tests Package.swift Examples IntegrationTests/Tests`: 0 violations in 129 files. `swift build --package-path IntegrationTests --build-tests`: complete.
    - next: /review
  timestamp: 2026-09-25T18:17:28.562942+00:00
depends_on:
- 01M3A6BZSVQR5RJ7TNBJ0Z9Y9Q
position_column: doing
position_ordinal: '80'
title: The final message names the agent and the run
---
## What
The Router renders a staged post as `[agents] start agent (<completionToken>) completed: <detail>`, with the token as `correlationID`. The reply of `start agent` gives the model only the run id, not the token. Thus the model cannot join a post to the run it started, and for a finished run `detail` is only the bare text. A parent that started two agents cannot tell which result came from which.

- In `Sources/FoundationModelsAgents/Run/AgentRun+FinalMessage.swift` `finalMessage(for:)`, make the `.finished` detail "Agent `name` (`id`) finished.\n\n<text>", the same form as `check agent`. Failed and cancelled posts already name the run.
- `AgentsToolText.cancel` `.alreadySettled` (`Sources/FoundationModelsAgents/Tool/AgentsToolText.swift`) now gives "`subject` ended before the cancel.\n\n`detail`", which would name the agent two times. Make it use the report of the run, or a detail with no name.
- Update plan.md §9.1 (the `check agent` row: the new progress text of `^j0z9y9q`) and §9.2 (the finished detail), the README, and the DocC article `TheFinalMessage.md`.

## Acceptance Criteria
- [x] The finished post starts with "Agent `name` (`id`) finished." and then holds the full text, also when longer than 4096 characters.
- [x] A parent's delivery prompt holds the names of both children when two finish.
- [x] A `cancel agent` of a run that already ended names the agent one time.

## Tests
- [x] Update `FinalMessageTests`, `NestedRunTests`, `ReadmeExampleTests`, and `AgentsToolOperationsTests` where they compare `detail` with the bare text or check the cancel answer.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.