---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m73e8aev5wha9848nbn7ftvk
  text: |-
    Research done. The real order of a run start:
    1. `AgentRun.make` calls `AgentSessionMaker.makeSession`. The Router writes `index.md` (with `agentSpawn`: the parent link that `RecordedChild` reads) synchronously in `makeSession`.
    2. `AgentRunner.start` puts the run in `openRuns` and calls `attach(changeHub)` (the run is visible to the host and in the background list of its caller).
    3. `begin` starts the driver task. `drive` subscribes to the session events (the run-event observer gets each event), then `mailTaskPrompt` posts the task mail.
    4. The pump of the Router takes the mail later. Only then does it write the `promptStarted` marker (`RoutedSessionActorPump.runFirstSubmission` → `recordPromptStart`). `FirstPromptReader` reads that marker or the `.prompt` entry. A mail that only waits in the queue has no record that it reads.
    Thus a kill between step 2 and step 4 leaves a listed child with no first prompt.

    The Router gives no way to write a task prompt at creation: `SessionRecord` fields are `internal(set)`, `SessionConfiguration` has no such field, and the only public writers of the record are tags, title, additional directories and the ended marker. The Router also gives no public lookup of the folder of a session from a `RouterSessionDirectory` (`TranscriptTree.sessionFolder` is `package`). The layout under an explicit recording root is flat: `<recordingRoot>/<sessionId>/` (`RoutedLLM.recordingDirectory(forSessionId:recordingRoot:)`). Discovery matches only `index.md`, so one more file in a session folder does not disturb the Router.

    The plan (the fallback of the card): `AgentRun.make` writes the task prompt to a file beside `index.md` in the session folder, before the run goes in the index. The restore reads `<AgentEnvironment.recordingRoot>/<sessionId>/` first, then the recorded first prompt of the Router. `prompts[sessionID]` from the host still wins.

    There is no seam that holds the pump before it takes the mail (no session hooks from Agents, and the scripted backend runs after the marker). Thus the deterministic tests hide the Router first prompt through `RestoreSource`, as `facadeFailsChildWithoutPrompt` does. That is the disk state of a kill before the take.
  timestamp: 2026-11-10T19:16:44.123447+00:00
- actor: claude-code
  id: 01m73epaf1sbpqb97xyx3xfkmc
  text: |-
    Implementation landed (not committed).
    - New `AgentTaskPromptRecord` (Sources/FoundationModelsAgents/Run/AgentTaskPromptRecord.swift): `task-prompt.md` beside the `index.md` of the session, UTF-8 text of the prompt. A session with no recording folder gets no record.
    - `AgentRun.make` writes the record right after `makeSession`, before it returns. Thus the record is on disk before `AgentRunner.start` puts the run in the index, before `attach(changeHub)`, and before the first observer event. A failed write logs `taskPromptNotRecorded` (agent name, run id, error type; no content) and the run goes on.
    - `RestoreSource` has a fourth read, `taskPrompt`, over `AgentEnvironment.recordingRoot` (`<root>/<session>/task-prompt.md`). `withFirstPrompts` uses the record first, then the listed first prompt, then `firstPrompt(of:)`. `prompts[sessionID]` still wins in the restore loop.
    - Limit: with `recordingRoot == nil` the restore cannot find the folder of a session (the Router has no public folder lookup), so it reads only the Router first prompt, as before. A host that restores runs sets the root.
    - `LoadingBoundaryTests`: the new file is exempt from the `FileManager` and `Data(contentsOf` rules, with the reason that it is a recording file, not an agent file.
    - Tests: two new end-to-end cases in RestoreEndToEndTests (a child of the host session, and a nested run), with the Router first prompt hidden. RED before the change: the run was not restored. GREEN after. The check "no instructions divergence event" was checked to fail with a wrong prompt. Four unit tests in AgentTaskPromptRecordTests. `facadeFailsChildWithoutPrompt` now hides the new record too. `secondRunner` sets the recording root, as a host does.
    - README restore text updated.

    ### implement — changed
    - evidence: `swift build --build-tests` no error, no warning in our code (only the known mlx "missing creator" note); `swift test` 933 tests in 121 suites passed.
    - next: /review
  timestamp: 2026-11-10T19:24:22.881487+00:00
- actor: claude-code
  id: 01m73ezycvmy2sq6nq37evx06z
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (28808c9): 1 finding (1 confirmed, 2 refuted) — Sources/FoundationModelsAgents/Run/AgentRunRestore+Interrupted.swift:313
    - next: implement the finding (replace `try?` with do/catch that logs a warning, keep the fallback), then review again.
  timestamp: 2026-11-10T19:29:38.203387+00:00
- actor: claude-code
  id: 01m73f0azpd8bj6acf5h7rb9n8
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — AgentTaskPromptRecord.swift (new), AgentRun.swift, AgentRun+Logging.swift, AgentRunRestore+Interrupted.swift, AgentsTelemetry.swift, README.md, 4 test files
    - test: green — root swift build --build-tests clean; swift test 933 passed in 121 suites; IntegrationTests build clean; RestoreEndToEndTests x3 stable
    - commit: 28808c9
    - review: findings — Sources/FoundationModelsAgents/Run/AgentRunRestore+Interrupted.swift:313
  timestamp: 2026-11-10T19:29:51.094361+00:00
- actor: claude-code
  id: 01m73f77dxzv1hrezxjrvxka7y
  text: |-
    Review finding fixed (not committed).
    - `recordedPrompt` in AgentRunRestore+Interrupted.swift had two `try?` reads: the task prompt record and the Router first prompt. Both now go through `readPrompt(of:record:read:)`: a do/catch that calls `logPromptReadFailure` and gives `nil`, thus the restore uses the next source. The fallback order is the same.
    - The warning record has the message `AgentsTelemetry.LogMessage.recordReadFailed`, the new metadata key `LogMetadataKey.recordName` (`task-prompt.md` or `router first prompt`), the session id, the caller session id, the error type and the error text, in the style of `logClaimReadFailure`. It never holds the prompt text.
    - AgentTaskPromptRecord.swift has no `try?`. Its read throws, and the caller now logs the error.
    - Test: `unreadableTaskPromptRecordIsLoggedAndSkipped` in RestoreEndToEndTests. It writes bytes that are not UTF-8 to the caller record, restores, and expects one warning, no failed child, and no instructions divergence (the Router prompt was used). RED: 0 warnings. GREEN after the fix. `cutChain` takes an optional `logger` for this test.

    ### implement — changed
    - evidence: AgentRunRestore+Interrupted.swift, AgentsTelemetry.swift, RestoreEndToEndTests.swift; `swift build --build-tests` no error, no warning in our code (only the known mlx "missing creator" note); `swift test` 934 tests in 121 suites passed.
    - next: /review
  timestamp: 2026-11-10T19:33:36.829762+00:00
position_column: doing
position_ordinal: '80'
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

## Review Findings (2026-11-10 13:27)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 3 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file

- [x] `Sources/FoundationModelsAgents/Run/AgentRunRestore+Interrupted.swift:313` `completeness/public-output-contract` — The task prompt record read is wrapped in `try?`, so a record that exists but cannot be read (for example, a file that is not UTF-8 text, which throws `ReadError.notText`) is dropped with no log. The restore then silently falls back to the listed or Router first prompt. The file already logs a comparable read failure (`logClaimReadFailure`), so an operator has no way to see that the intended record was ignored. Replace `try?` with a do/catch that logs the failure at warning level (the record name and the session id, never the record text) and then uses the next source. Keep the fallback, so the restore still goes on.
