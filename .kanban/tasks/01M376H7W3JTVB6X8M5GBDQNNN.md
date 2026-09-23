---
assignees:
- claude-code
depends_on:
- 01M376GY7KFDSK19S6JW03FKFQ
position_column: todo
position_ordinal: 8f80
title: AgentsTool operations and the final message through ToolContext
---
## What
Plan.md §9.1 (the operations table), §9.2 (the final message). M4. The operation declarations exist from the `AgentsTool.make` task; this task writes their bodies.

- In `Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift` implement `list agents`, `start agent`, `check agent`, `cancel agent`. Verb aliases: `stop` → `cancel`, `run` → `start`, `status` → `check`, `show` → `list`.
- Answers are plain text through `CorrectiveOutcome` (`.success` or `.corrective(String)`). A correction is a text result, never a thrown error, never a post. The wrapper decodes the JSON string that `OperationTool` makes, as Skills does.
- `start agent`: read `ToolContext.current`, give it to the run, start the run as a runner task, and return at once. The id in the answer is the run id (the session `ULID`). The runner index maps the `completionToken` of the call to the run. It posts nothing during the call.
- Create `Sources/FoundationModelsAgents/Run/AgentRun+FinalMessage.swift`: on finish the run calls `context.post(_:)` one time with a `.completed` `OperationEvent` whose `detail` is the full text. Failed: `outcome` set and "Agent `name` (`id`) failed: reason." Cancelled: "Agent `name` (`id`) was cancelled." Post, then mark the run finished.
- Outside a Router session (`ToolContext.current == nil`) `start agent` works the same, and no final message is posted.
- `check agent` with an id never waits. `cancel agent` gives the `CancelOutcome`.
- A changed agent after a reload runs with the new definition; a removed agent gives a corrective with the current names.
- The run-limit and depth correctives, the running texts, `check agent` with no id, and caller isolation come in later tasks.

## Acceptance Criteria
- [ ] Success texts: `list agents` lines and the delegation sentence; "No agents are available."; the `start agent` text; the finished, failed, and cancelled `check agent` texts.
- [ ] Corrective texts: an unknown or removed name with the available names; a name outside `Agent(a, b)`; a blank prompt; an unknown id.
- [ ] Each verb alias reaches its operation.
- [ ] The answer text is plain text, not a JSON string (the wrapper decodes it; plan.md §16).
- [ ] `start agent` returns before the scripted child turn ends (child gated), and posts nothing during its call.
- [ ] `check agent` on a gated run returns at once.
- [ ] The final message is the only post and holds the full text, also when longer than 4096 characters (plan.md §16).
- [ ] A failed run and a cancelled run each post one `.completed`.
- [ ] The calling session emits `runSettled` with no mailbox run behind it, and its next prompt reads the post (plan.md §16).
- [ ] A post that arrives during a turn of the calling session stays staged and is read by the next prompt (plan.md §16).

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentsToolOperationsTests.swift` and `Tests/FoundationModelsAgentsTests/FinalMessageTests.swift`, with a scripted root session that calls the tool.
- [ ] Run `swift test --filter "AgentsToolOperationsTests|FinalMessageTests"`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.