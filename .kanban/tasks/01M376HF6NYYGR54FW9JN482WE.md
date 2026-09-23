---
assignees:
- claude-code
depends_on:
- 01M376H7W3JTVB6X8M5GBDQNNN
position_column: todo
position_ordinal: '9080'
title: 'Scheduler: maxConcurrentAgents, caller isolation, cancelRuns(caller:), check with no id'
---
## What
Plan.md §9.2 (a closed caller), §9.3 (the limit, the index). M5, first part.

- In `Sources/FoundationModelsAgents/Run/AgentRunner.swift` (or a new `AgentRunner+Scheduling.swift`):
  - `maxConcurrentAgents` counts runs with a turn in operation. Only `start agent` checks it. At the limit the tool gives the corrective: "`N` agents are working now, and that is the limit. Do this part of the task yourself, or start the agent when one of them finishes." No queue. Host-driven `runner.start` does not check it.
  - `cancelRuns(caller: ULID)`: cancel each open run of that caller.
- In `Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift`:
  - `check agent` with no `id`: one block for each run of this caller.
  - `check agent` and `cancel agent` with an id of a different caller: the same corrective as an unknown id, with this caller's ids.
  - Running text: "is running: `lastEvent`".
- Verify (plan.md §16): a post into a closed session does no harm.

## Acceptance Criteria
- [ ] With `maxConcurrentAgents` 2 and two gated runs, a third `start agent` gives the corrective; after one finishes, a new start succeeds.
- [ ] Caller A cannot check or cancel a run of caller B.
- [ ] `check agent` with no id lists only the runs of the caller.
- [ ] `cancelRuns(caller:)` cancels only that caller's runs.
- [ ] A run that finishes after its caller session closed does not crash and gives its record.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentSchedulingTests.swift` covers each criterion.
- [ ] Run `swift test --filter AgentSchedulingTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.