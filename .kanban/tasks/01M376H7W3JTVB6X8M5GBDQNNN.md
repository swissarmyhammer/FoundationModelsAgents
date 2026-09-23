---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37sc571ak2z4gpakzac97ej
  text: |-
    Research and implementation notes:
    - The Skills `PlainTextOperations` is internal to Skills. All four agents operations give text, thus `AgentsTool.call` decodes each answer that is one JSON string, and keeps a resolver corrective as it is.
    - The default `OperationResolver` aliases map `show` to `get`. `AgentsTool.verbAliases` puts `show` → `list` over it, with `stop` → `cancel`, `run` → `start`, `status` → `check`.
    - `AgentRun` now keeps `context` (the `ToolContext` of the start call). The turn task closes the session, posts the final message (`AgentRun+FinalMessage.swift`), then records the final state. Outcome: `.succeeded`, `.failed`, `.cancelled`.
    - `cancel agent` gives a `CancelOutcome` from `AgentRun.requestCancel()`: `.reported(.cancelled)` for a run in operation, `.alreadySettled(finalMessage)` for an ended run.
    - New runner call `runs(caller:)` (open runs and records) gives the ids for the unknown-id corrective.
    - The run posts the final message into the caller transcript with the token, and the Router emits `runSettled`. The next prompt holds the preamble line `[agents] start agent (<token>) completed: <detail>`.
    - The lineage test in `AgentRunTests+Lineage.swift` posted by hand. The run now posts itself, thus the test reads the post of the run.
  timestamp: 2026-09-23T18:45:14.593637+00:00
- actor: claude-code
  id: 01m37sc7z0anbxzf957beyw1cb
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsAgents/Tool/{AgentsTool,AgentsToolContext,AgentsToolDescription,AgentsToolOperations,AgentsToolText}.swift, Run/{AgentRun,AgentRun+FinalMessage,AgentRunFailure,AgentRunner}.swift, Tests/FoundationModelsAgentsTests/{AgentsToolOperationsTests,FinalMessageTests,AgentRunTests+Lineage}.swift, Support/AgentsToolHarness.swift. `swift test --filter "AgentsToolOperationsTests|FinalMessageTests|AgentRunTests"`: 35 tests pass. swiftlint: 0 violations.
    - next: test
  timestamp: 2026-09-23T18:45:17.408554+00:00
- actor: claude-code
  id: 01m37sdczhbpe0x4my242kaz5k
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors`: 210 tests in 26 suites pass, 0 failed, 0 skipped. `swiftlint lint --quiet Sources Tests Examples`: 0 violations.
    - next: commit
  timestamp: 2026-09-23T18:45:55.313481+00:00
- actor: claude-code
  id: 01m37sdna55dt3x2ksb9byw2ks
  text: |-
    ### commit — changed
    - evidence: 76dbb9e feat(tool): the agents operations answer in plain text, and a run posts one final message through ToolContext
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T18:46:03.845409+00:00
- actor: claude-code
  id: 01m37smbs03c39g6s0svysanw6
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD: 0 findings, 0 confirmed, 0 refuted (7 attempted, 13 files reviewed). No prior Review Findings sections.
    - next: done

    ### finish iteration 1 — clean
    - implement: changed (11 source and test files)
    - test: green (swift test -Xswiftc -warnings-as-errors: 210 tests in 26 suites pass; swiftlint 0 violations)
    - commit: changed (76dbb9e)
    - review: clean (0 findings)
  timestamp: 2026-09-23T18:49:43.456871+00:00
depends_on:
- 01M376GY7KFDSK19S6JW03FKFQ
position_column: done
position_ordinal: '9180'
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
- [x] Success texts: `list agents` lines and the delegation sentence; "No agents are available."; the `start agent` text; the finished, failed, and cancelled `check agent` texts.
- [x] Corrective texts: an unknown or removed name with the available names; a name outside `Agent(a, b)`; a blank prompt; an unknown id.
- [x] Each verb alias reaches its operation.
- [x] The answer text is plain text, not a JSON string (the wrapper decodes it; plan.md §16).
- [x] `start agent` returns before the scripted child turn ends (child gated), and posts nothing during its call.
- [x] `check agent` on a gated run returns at once.
- [x] The final message is the only post and holds the full text, also when longer than 4096 characters (plan.md §16).
- [x] A failed run and a cancelled run each post one `.completed`.
- [x] The calling session emits `runSettled` with no mailbox run behind it, and its next prompt reads the post (plan.md §16).
- [x] A post that arrives during a turn of the calling session stays staged and is read by the next prompt (plan.md §16).

## Tests
- [x] `Tests/FoundationModelsAgentsTests/AgentsToolOperationsTests.swift` and `Tests/FoundationModelsAgentsTests/FinalMessageTests.swift`, with a scripted root session that calls the tool.
- [x] Run `swift test --filter "AgentsToolOperationsTests|FinalMessageTests"`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.