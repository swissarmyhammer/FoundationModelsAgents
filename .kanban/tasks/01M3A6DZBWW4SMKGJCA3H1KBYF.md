---
assignees:
- claude-code
depends_on:
- 01M3A6CJRDYEA2YJ9ANY4XPK60
- 01M3A6DF0468875FVSZAYPVKYX
position_column: todo
position_ordinal: 8b80
title: Live tests check the parent's final answer, and the tool description
---
## What
Two live suites in `IntegrationTests/Tests/AgentsIntegrationTests/` check too little.
- `LiveNestedTests`: `lead.result()` is discarded, and the lead's answer word is never checked. Nothing proves that the lead waited for the leaf or read its post in a delivery turn.
- `FullCircleTests`: the reply of `dispatchNextPrompt()` is discarded. The root prompt gives the model the exact JSON of the call, so the tool description is never tested.

Change them:
- `LiveNestedTests`: check that the lead's final answer holds the leaf's word, and that the leaf's post comes before the lead's final answer in the lead transcript.
- `FullCircleTests`: check that the root's reply after the delivery holds the sub-agent's word. Add one case where the root prompt names the task only ("ask the X agent for …"), with no JSON, and the root still calls `start agent` from the tool description.
- Keep the design rules of the live suites: one at a time, tool calls that a test needs on the standard model, and answer-only agents with no tools (after `^aypvkyx`, they need no `disallowedTools: Agent`).

## Acceptance Criteria
- [ ] Both checks fail if the lead does not read the leaf's result. Prove this one time with a temporary change during development, and record the failing output as a comment on this task.
- [ ] The no-JSON case passes on this host in 3 runs in a row.

## Tests
- [ ] The two changed suites.
- [ ] Run `cd IntegrationTests && swift test` 3 times. Expected: pass each time. Report the real results.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.