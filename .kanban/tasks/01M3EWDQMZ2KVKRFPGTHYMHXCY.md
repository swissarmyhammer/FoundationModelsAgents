---
assignees:
- claude-code
position_column: todo
position_ordinal: '9280'
title: 'Live tests: remove the transcript.jsonl read race'
---
## What
In a full run of `cd IntegrationTests && swift test` on 2026-09-26 (during task ^aypvkyx), two live tests failed one time with the same error: `NSCocoaErrorDomain Code=260 ... "transcript.jsonl" couldn't be opened ... No such file or directory`.
- `FullCircleTests.delegationGoesFullCircle`
- `LiveNestedTests.agentSpawnLinksThreeSessions`

Each test passed when it ran alone, and two more full runs passed 11 of 11. Thus the test reads the session recording before the recording is on disk. A test that fails one time in three is a defect, not a pass.

- Find where these two tests (or their support in `IntegrationTests/Tests/AgentsIntegrationTests/Support/`) read `transcript.jsonl`.
- Make the read wait for the recording in a deterministic way: use a Router API that tells when the recording of a session is written (for example, await the session `close()` or a flush), or read the transcript through the session and not the file. Do not add a sleep or a retry loop with a fixed time.
- If the Router gives no way to know that the file is written, stop and record this on the task as a Router need.

## Acceptance Criteria
- [ ] The two tests do not read `transcript.jsonl` before the recording of that session is complete.
- [ ] 5 full runs of `cd IntegrationTests && swift test` in a row pass 11 of 11.

## Tests
- [ ] Change `FullCircleTests.swift`, `LiveNestedTests.swift`, and the support code that they use.
- [ ] Run `cd IntegrationTests && swift test` 5 times. Expected: pass each time. Report the real results.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.