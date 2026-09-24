---
assignees:
- claude-code
depends_on:
- 01M3A6D0PH2N6Z6BWHGJ8KGEGV
- 01M3A6CQGZZC4VNCQM2Z6EPJ2M
position_column: todo
position_ordinal: '8980'
title: 'Decision B: state in the plan that the run limit does not count the calling run'
---
## Decision (recommended; confirm or change before /finish)
`AgentRunner.startWithinLimit` (`Sources/FoundationModelsAgents/Run/AgentRunner.swift`) does not count the run that calls `start agent`. This lets two sibling runs that wait for their children let those children start. Its doc comment already states the rule and the reason. Plan §9.3 says only that the limit "counts runs with a turn in operation". The recommendation: keep the behavior, write it into the plan and the DocC article, and prove it with a test.

## What
- plan.md §9.3 and the DocC article `DelegatingWithTheAgentsTool.md`: the limit counts the runs that are working, except the run that calls `start agent`. With `maxConcurrentAgents: 1`, a parent and one child can work together.
- Check that the doc comment of `startWithinLimit` says the same; change it only if it differs.

## Acceptance Criteria
- [ ] The plan, the DocC article, and the doc comment state the same rule.
- [ ] A test with `maxConcurrentAgents: 1` shows that a parent can start one child, and that a second start by a different caller at the same time gets the limit corrective.

## Tests
- [ ] A case in `Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift`.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.