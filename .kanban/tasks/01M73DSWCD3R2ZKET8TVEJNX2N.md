---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: A run records its task prompt before it is announced, so a kill after the announcement restores it
---
## What
Defect from FoundationModelsACPAgent (agreed with testudoapp-75). A run is announced (its session and its `running` state show to the host, and it is in the background list of its caller) before its task prompt is recorded. Today the restore reads the task prompt of a child as its recorded first prompt (`RecordedChild.firstPrompt`, from the session directory: `source.firstPrompt`, in `Sources/FoundationModelsAgents/Run/AgentRunRestore+Interrupted.swift`). That prompt exists only after the first generate. When the process is killed between the announcement and the first generate, `restoreInterrupted` ends the claim as lost and records `FailedChild.promptNotRecordedReason`. The run never comes back. Evidence: FoundationModelsACPClient `aKilledAgentResumesTheNestedRunWithItsTree` (a grandchild announced `running`, then the kill, then `restoreFailure` and an empty result).

- Find the order of the start of a run: the creation of the child session, the record of the parent link (`RecordedChild`, `parentToolCallId`), the announcement to the host, the run-event observer, and the first submit (`AgentRun`, `AgentRunner`, `AgentSessionMaker`, `ChildSessionWork`, `AgentRunRestore`).
- Record the task prompt durably before the run is announced, for a run that the host starts and for a nested run. Use the session record that the restore already reads (for example the session record or sidecar of the Router, if it can hold the task prompt at creation), so that `RecordedChild.firstPrompt` (or a new recorded field) has the prompt before any announcement. Do not add a second file format if the existing record can hold it. If the Router does not give a way to write it, record the prompt in the recording root of the run (`AgentEnvironment` recording root) in the same form as the other run records, and make the restore read it first.
- The restore uses the recorded task prompt; `prompts[child.sessionID]` from the host still wins when given.
- If the order cannot change (for example the announcement must come before the session exists), stop and tell the reason on this task, so ACPAgent can give `prompts:` to `restoreInterrupted` as a fallback.

## Acceptance Criteria
- [ ] A run that is stopped after its announcement and before its first generate is restored by `restoreInterrupted` with its task prompt, for a run that the host starts and for a nested run (a child of a run).
- [ ] No `FailedChild.promptNotRecordedReason` for such a run.
- [ ] A run that is stopped after its first generate restores as before.

## Tests
- [ ] A deterministic test in `Tests/FoundationModelsAgentsTests/` (next to the restore tests, for example `RestoreEndToEndTests.swift`): hold the first generate of the child with the scripted profile, wait for the announcement event, stop the process state (stop the runner and drop the live objects, as the existing restore tests do), call `restoreInterrupted`, and expect the run back with its task prompt. One case for a host-started run and one for a nested run. No wall-clock waits (test rule T1).
- [ ] `swift build --build-tests` gives no error and no warning in our code. `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1 #bug