---
assignees:
- claude-code
depends_on:
- 01M3A6BZSVQR5RJ7TNBJ0Z9Y9Q
position_column: todo
position_ordinal: '8180'
title: The final message names the agent and the run
---
## What
The Router renders a staged post as `[agents] start agent (<completionToken>) completed: <detail>`, with the token as `correlationID`. The reply of `start agent` gives the model only the run id, not the token. Thus the model cannot join a post to the run it started, and for a finished run `detail` is only the bare text. A parent that started two agents cannot tell which result came from which.

- In `Sources/FoundationModelsAgents/Run/AgentRun+FinalMessage.swift` `finalMessage(for:)`, make the `.finished` detail "Agent `name` (`id`) finished.\n\n<text>", the same form as `check agent`. Failed and cancelled posts already name the run.
- `AgentsToolText.cancel` `.alreadySettled` (`Sources/FoundationModelsAgents/Tool/AgentsToolText.swift`) now gives "`subject` ended before the cancel.\n\n`detail`", which would name the agent two times. Make it use the report of the run, or a detail with no name.
- Update plan.md §9.1 (the `check agent` row: the new progress text of `^j0z9y9q`) and §9.2 (the finished detail), the README, and the DocC article `TheFinalMessage.md`.

## Acceptance Criteria
- [ ] The finished post starts with "Agent `name` (`id`) finished." and then holds the full text, also when longer than 4096 characters.
- [ ] A parent's delivery prompt holds the names of both children when two finish.
- [ ] A `cancel agent` of a run that already ended names the agent one time.

## Tests
- [ ] Update `FinalMessageTests`, `NestedRunTests`, `ReadmeExampleTests`, and `AgentsToolOperationsTests` where they compare `detail` with the bare text or check the cancel answer.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.