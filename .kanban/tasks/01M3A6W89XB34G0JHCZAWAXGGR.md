---
assignees:
- claude-code
depends_on:
- 01M3A6D0PH2N6Z6BWHGJ8KGEGV
- 01M3A6DKKKADT8YYMXA9GEAWDJ
position_column: todo
position_ordinal: '9180'
title: Remove the completion-token index that only tests use
---
## What
`AgentRunner.run(completionToken:)` and its token map (`Sources/FoundationModelsAgents/Run/AgentRunner.swift`) are used only by `AgentRunnerTests`. Plan §9.2 ("The runner index maps the `completionToken` of the call to the run") and §9.3 describe the index.

- Search the code for a production caller. If there is none, remove the method, the map, the two test calls in `AgentRunnerTests.swift`, and the sentences in plan §9.2 and §9.3.
- If a production caller needs it, keep it and add a test through that caller. Write the reason as a comment on this task.

## Acceptance Criteria
- [ ] The token index is removed, or it has a production caller that a test covers.
- [ ] Plan §9.2 and §9.3 match the code.

## Tests
- [ ] Update `AgentRunnerTests.swift`.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.