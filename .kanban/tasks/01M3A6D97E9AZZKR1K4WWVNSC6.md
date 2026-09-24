---
assignees:
- claude-code
depends_on:
- 01M3A6C3W4FTNNC249NNVFWH3M
- 01M3A6CJRDYEA2YJ9ANY4XPK60
position_column: todo
position_ordinal: '8780'
title: No agents tool at maxDepth; cancel agent reports only a cancel that happened
---
## What
Two small lifecycle defects.

1. **A run at `maxDepth` still gets the `agents` tool** (`Sources/FoundationModelsAgents/Run/AgentSessionMaker.swift` `tools(for:as:)`). Each start it tries gives a corrective. That wastes context and invites retries. Pass no `agents` tool factory when `request.depth >= environment.maxDepth`. `start agent` keeps its depth corrective for a direct call.
2. **`requestCancel` can report a cancel that did not happen** (`Run/AgentRun.swift` `requestCancel()`). After `drive` returns, the run cancels its children, closes its session, and posts. During all of that the state stays `.running` until `end(in:)`. A cancel in that window answers "The cancel … was sent (cancelled)", but the run already has its result. Fix: record the settled final state in the run's storage at once when `drive` returns. `requestCancel()` and the report read it; a cancel after that point answers that the run already ended, with its end state.

## Acceptance Criteria
- [ ] A run at `maxDepth` has no `agents` tool in its session; a run below it has one.
- [ ] A cancel after the final state of the turn is known answers that the run already ended, with that state, during the child cancel, the session close, and the post.

## Tests
- [ ] Update `NestedRunTests+Limits.swift` `grandchildAboveMaxDepthGivesCorrective` (the grandchild has no tool now), and add a case that the depth corrective still comes from a direct call.
- [ ] A case in `AgentsToolOperationsTests.swift` for a cancel after the final state is known (hold the run in its cleanup with a gate on a child or a test hook).
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.