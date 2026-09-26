---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fh8mt5h2rpmba1m1zek1vn
  text: |-
    Research:
    - `AgentRun.finishAfterChildren` runs a delivery turn for each child post, then a final-answer turn with `AgentRun.finalAnswerPrompt`. `lead.result()` is the text of that final-answer turn.
    - The lead body now says "write the single word STARTED". Thus the final answer of lead cannot show that lead read the post of leaf. The lead body must tell lead to answer with the word that the helper gives, and must not hold that word.
    - In a transcript, each `TranscriptEvent` has a public `seq`. The `.prompt` entry of a delivery turn carries the post as an operation event with the correlation id `agentSpawn.parentToolCallId`. The final answer is the last `.response` event with `mirrorsTranscriptEntry`. Thus "read before final answer" is a compare of two `seq` values.
    - `RoutedSession.dispatchNextPrompt()` gives `String?`: the text of the delivery turn of the root, or `nil` when no work was queued.
    - The temporary change for the proof: `AgentRun.postFinalMessage(for:)` in `Sources/FoundationModelsAgents/Run/AgentRun+FinalMessage.swift` posts nothing. Then no parent reads the result of a child.
  timestamp: 2026-09-26T18:57:26.341881+00:00
- actor: claude-code
  id: 01m3fhv1esa8q0ap36r0vp3e01
  text: |-
    Proof: the checks fail when the parent does not read the result of the child.

    Temporary change (now reverted, `git diff -- Sources` is empty): in `AgentRun.postFinalMessage(for:)` (`Sources/FoundationModelsAgents/Run/AgentRun+FinalMessage.swift`), `await context.post(message)` became `_ = (context, message)`. Thus no run posts its final message, and no parent reads it.

    Command: `cd IntegrationTests && swift test --filter "FullCircleTests|LiveNestedTests"`. Result: 3 tests, 3 failed, 13 issues. The new checks in the output:

    ```
    LiveNestedTests.swift:79: Expectation failed: leadText.localizedCaseInsensitiveContains(Self.leafWord)
      The final answer of lead was: The agent's final message will be the single word answer. I will provide it when received.
      leadText → "The agent's final message will be the single word answer. I will provide it when received."
      Self.leafWord → "PAPAYA"
    LiveNestedTests.swift:81: Expectation failed: try LiveRecording.readsPost(leafSpawn.parentToolCallId, beforeFinalAnswerIn: leadDirectory)
    FullCircleTests.swift:113 (JSON case): Expectation failed: reply?.localizedCaseInsensitiveContains(LiveWordTool.word) == true
      The reply of the root was: nil
    FullCircleTests.swift:113 (no-JSON case): Expectation failed: reply?.localizedCaseInsensitiveContains(LiveWordTool.word) == true
      The reply of the root was: nil
    ```

    The earlier checks also failed (posted, read, leadCalls, leafCalls: each `[]`).

    What did not work, and why:
    - With the old lead body ("write the single word STARTED"), the new LiveNested checks passed, because the final-answer turn made lead give PAPAYA. But the body told lead to write a different word, thus the check depended on luck. The body now tells lead to answer with the word of the helper.
    - A FullCircle root prompt that said "When the final message of the agent comes, answer with the single word that the agent gives" failed. The root model guessed a word ("example", "sunflower") at the end of its first turn, and kept that guess in the delivery turn, also when the post said MANGO. In one run it also called `start agent` two times. The sentence "You do not know the secret word. Do not guess it." did not stop the guess. The fix: the root writes only the word WAITING after the call. Then the delivery turn gives "The secret word is MANGO." or "MANGO".
    - Discovery: `TranscriptEvent.seq` of a `.toolOutput` post can be lower than the `seq` of the entries of the turn that was open when the post came (the Router records the turn entries at the end of the turn). Thus `readsPost(_:beforeFinalAnswerIn:)` compares the `.prompt` entry that reads the post, not the `.toolOutput` entry, with the last `.response`.
    - Discovery: in the no-JSON case, the root model first calls a tool named "start agent" (the op name). The Router rejects it with `undeclared_tool`, and the model then calls the `agents` tool correctly. The test passes, but the tool description could name the tool more clearly. Recorded as a new task.
  timestamp: 2026-09-26T19:07:29.113688+00:00
- actor: claude-code
  id: 01m3fjg4zs5q5kpewgm5qqges4
  text: |-
    Full live runs, first set (lead body "When the final message of the helper comes, answer with the single word that the helper gives."): run 1 passed 12/12, run 2 passed 12/12, run 3 failed 1 issue of 12 tests. LiveNestedTests.swift:79: the final answer of lead was "yes". The lead transcript shows the cause: at the end of its task turn, lead wrote "The final answer from the agent is: \"yes\"." (a guess), and kept "yes" in the delivery turn and in the final-answer turn, also when the post said PAPAYA. This is the same guess as the root in FullCircle.

    Fix: one shared instruction `LiveHarness.waitInstruction` ("After the call, write only the word WAITING. When the final message of the agent comes, answer with the single word that the agent gives."). The lead body and both FullCircle root prompts use it. The 3-run count starts again from zero with this change.
  timestamp: 2026-09-26T19:19:00.857556+00:00
- actor: claude-code
  id: 01m3fjk581nqqq5kpdprwj7h2w
  text: |-
    Proof, second time, on the final test code (with `LiveHarness.waitInstruction`). The same temporary change in `AgentRun.postFinalMessage(for:)` (no post). Now reverted; `git diff -- Sources` is empty.

    `cd IntegrationTests && swift test --filter "FullCircleTests|LiveNestedTests"`: 3 tests, 3 failed, 13 issues. The new checks:

    ```
    LiveNestedTests.swift:79: Expectation failed: leadText.localizedCaseInsensitiveContains(Self.leafWord)
      The final answer of lead was: WAITING
      leadText → "WAITING"
    LiveNestedTests.swift:82: Expectation failed: try LiveRecording.readsPost(leafSpawn.parentToolCallId, beforeFinalAnswerIn: leadDirectory)
    FullCircleTests.swift:103 (JSON case): Expectation failed: reply?.localizedCaseInsensitiveContains(LiveWordTool.word) == true
      The reply of the root was: nil
    FullCircleTests.swift:103 (no-JSON case): Expectation failed: reply?.localizedCaseInsensitiveContains(LiveWordTool.word) == true
      The reply of the root was: nil
    ```
  timestamp: 2026-09-26T19:20:39.425641+00:00
- actor: claude-code
  id: 01m3fk5ppcd29ywkysndmfy4vg
  text: |-
    ### implement — changed
    - evidence: 4 files — IntegrationTests/Tests/AgentsIntegrationTests/LiveNestedTests.swift, IntegrationTests/Tests/AgentsIntegrationTests/FullCircleTests.swift, IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveRecording.swift (new `readsPost(_:beforeFinalAnswerIn:)`), IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveHarness.swift (new `waitWord`, `waitInstruction`). No change under Sources (the temporary proof change is reverted). Root: `swift build -Xswiftc -warnings-as-errors` complete; `swift test -Xswiftc -warnings-as-errors` 359 tests in 49 suites passed. swiftlint: 0 violations in 123 files (Sources Tests Package.swift Examples) and 0 in the 4 changed IntegrationTests files. Live, final code, 3 full runs in a row of `cd IntegrationTests && swift test`: run 1 12/12 passed (139.2 s), run 2 12/12 passed (165.8 s), run 3 12/12 passed (164.9 s). The no-JSON case passed in each of the 3 runs. An earlier set of runs with the previous lead body gave 12/12, 12/12, then 1 failure (lead guessed "yes"); that led to `waitInstruction`, and the count started again. Proof of failure without the post: recorded in two comments above (3 tests failed, 13 issues each time).
    - new task: ^p3ww0ar (the model first calls the op name "start agent" as a tool in the no-JSON case).
    - next: /review
  timestamp: 2026-09-26T19:30:47.116178+00:00
depends_on:
- 01M3A6CJRDYEA2YJ9ANY4XPK60
- 01M3A6DF0468875FVSZAYPVKYX
position_column: doing
position_ordinal: '80'
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
- [x] Both checks fail if the lead does not read the leaf's result. Prove this one time with a temporary change during development, and record the failing output as a comment on this task.
- [x] The no-JSON case passes on this host in 3 runs in a row.

## Tests
- [x] The two changed suites.
- [x] Run `cd IntegrationTests && swift test` 3 times. Expected: pass each time. Report the real results.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.