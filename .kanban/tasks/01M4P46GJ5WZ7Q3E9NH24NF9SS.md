---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4p5316nfjy9d5s451hjqhf7
  text: |-
    Research:
    - FoundationModelsMultitool (sibling checkout) does not have the injection wording yet. A grep for "injects its result" finds nothing. Multitool still has "end your answer" texts (Execute.swift, MultiTool+SandboxGlobals.swift). Thus this task uses the user-approved text verbatim as the pending text.
    - The final wording must still be confirmed with the session foundationmodelsmultitool-a4 before merge. No message was sent to that session.
    - The completion token is in the `completionToken` field of the pending envelope. The tests read the token from that field (ScriptedTranscriptText.completionToken, AgentRun+Drive pendingTokens). No code reads the token from the `next` text. Thus the new `next` text can drop the `check agent` call and the token.
    - `AgentsTool.collectInstruction(forCompletionToken:)` is the witness of the Router `BackgroundTool` requirement, so its signature stays.
    - Other texts to change: doc comments in AgentsToolText.swift and AgentsTool.swift, the test doc comments in AgentsToolMountTests.swift, TheFinalMessage.md ("but to end its answer") and DelegatingWithTheAgentsTool.md ("and to end its answer ... check agent call for the completion token").
    - Texts that stay: "ends when this answer ends" in RunningAnAgent.md and the AgentRun doc comments describe the run lifecycle for the host. They do not tell the model to end an answer.
  timestamp: 2026-10-11T18:55:02.357271+00:00
- actor: claude-code
  id: 01m4p5n7tyhgfv37r8ejxejhhr
  text: |-
    Implementation:
    - AgentsToolText.collectInstruction is now a `static let` with the user-approved text, word for word. It does not name the completion token and does not tell the model to call `check agent`. AgentsTool.collectInstruction(forCompletionToken:) keeps its signature (the Router `BackgroundTool` requirement) and gives that text for each token.
    - AgentsToolDescription fixed sentences: the "after you end your answer / your last turn" sentences are replaced with injection-model sentences. The description still lists `check agent` as the way to see the state of a run, but it does not tell the model to call a tool to wait.
    - DocC: TheFinalMessage.md and DelegatingWithTheAgentsTool.md now describe the injection model. A first full run failed in DocumentationTests because the claim "The final message comes to the calling session as mail." is pinned word for word. That sentence is kept as one sentence now.
    - Texts that stay (they describe the Router lifecycle for the host, not an instruction to the model): RunningAnAgent.md "ends when this answer ends", AgentRun+Drive.swift doc comment, CheckAgentProgressTests and NestedRunTests+Messages test names.
    - OPEN: the final wording must still be confirmed with the session foundationmodelsmultitool-a4. No message was sent to that session. Multitool still has "end your answer" texts in Execute.swift and MultiTool+SandboxGlobals.swift.
    - `swift test`: 498 tests in 68 suites passed. The one build warning, "missing creator for mutated node ... mlx-swift_Cmlx.bundle", comes from the SwiftPM build graph of the mlx-swift dependency, not from the code of this package.
  timestamp: 2026-10-11T19:04:58.974901+00:00
- actor: claude-code
  id: 01m4p5nb9tzv4716zytcy62qbg
  text: |-
    ### implement — changed
    - evidence: 7 files — AgentsToolText.swift, AgentsTool.swift, AgentsToolDescription.swift, TheFinalMessage.md, DelegatingWithTheAgentsTool.md, AgentsToolMountTests.swift, AgentsToolDescriptionTests.swift. `swift test`: 498 tests in 68 suites passed.
    - next: /review. Before merge, confirm the final wording with the session foundationmodelsmultitool-a4.
  timestamp: 2026-10-11T19:05:02.522119+00:00
- actor: claude-code
  id: 01m4p63mgkxsm6rbbcna5mqdsw
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (9cf7ee3); 2 findings, 2 confirmed, 0 refuted — Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift:93, Sources/FoundationModelsAgents/Tool/AgentsToolText.swift:130 (duplication/duplication). Blocker: the wording confirmation with the session foundationmodelsmultitool-a4 is open. A person must do it.
    - next: Put the shared injection sentences in one constant. Use it from collectInstruction and fixedSentences. Update the tests. Then review again.
  timestamp: 2026-10-11T19:12:50.707323+00:00
- actor: claude-code
  id: 01m4p640hzjybjpvmzkb5pvtb8
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 7 files
    - test: green — swift test, 498 tests in 68 suites passed
    - commit: 9cf7ee3
    - review: findings — Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift:93, Sources/FoundationModelsAgents/Tool/AgentsToolText.swift:130; blocker — Multitool wording confirmation (foundationmodelsmultitool-a4) open
  timestamp: 2026-10-11T19:13:03.039023+00:00
- actor: claude-code
  id: 01m4p6eadvs31jcs76r5sjhgw5
  text: |-
    Duplication findings, implementation:
    - New constant `AgentsToolText.injectionSentences` holds the injection and do-nothing sentences one time. `collectInstruction` is now "This is not the result. " + `injectionSentences`. The pending text stays word for word the same as the text that the user approved.
    - `AgentsToolDescription.fixedSentences` now uses `AgentsToolText.injectionSentences` after its own opening: "Else the call is not the result: the agent works in the background." The old shorter copy in the description ("so do not call a tool to wait for it ...") is gone. Thus the description now has the full approved injection sentences.
    - The description still ends with the `check agent` state sentence, as before. It now comes after "Do not call a tool to wait or to check." A person can decide in the Multitool confirmation if the description must keep that sentence.
    - Tests: new test support constant `PinnedInjectionText.sentences` (Tests/.../Support/PinnedInjectionText.swift) pins the sentences word for word one time. `AgentsToolMountTests.collectSentence` and `AgentsToolDescriptionTests.fixedSentences` both use it. New test `theFixedSentencesAndThePendingTextShareTheInjectionSentences` checks that both texts hold `AgentsToolText.injectionSentences`. RED was a compile failure (no member `injectionSentences`).
    - `swift test`: 499 tests in 68 suites passed. The one build warning "missing creator for mutated node ... mlx-swift_Cmlx.bundle" comes from the SwiftPM build graph of the mlx-swift dependency.
    - The blocker (confirmation with the session foundationmodelsmultitool-a4) stays open. Only a person can do it. No message was sent to that session.
  timestamp: 2026-10-11T19:18:40.827195+00:00
- actor: claude-code
  id: 01m4p6ecwt9epmv3knfnr23k57
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsAgents/Tool/AgentsToolText.swift, Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift, Tests/FoundationModelsAgentsTests/AgentsToolMountTests.swift, Tests/FoundationModelsAgentsTests/AgentsToolDescriptionTests.swift, Tests/FoundationModelsAgentsTests/Support/PinnedInjectionText.swift (new). `swift test`: 499 tests in 68 suites passed. Both duplication findings checked.
    - next: /review. The blocker (Multitool wording confirmation with foundationmodelsmultitool-a4) is open for a person.
  timestamp: 2026-10-11T19:18:43.354093+00:00
position_column: doing
position_ordinal: '80'
title: Change the "end your answer" texts of start agent to the injection model
---
## Reason

A SWE-bench run (no-otel-1011, 2026-10-11) showed that the model loops when a pending text tells it to "end your answer". In one instance, the model made 73 no-op tool calls.

The user decided these rules:
- There are no turns. There are only async queues.
- Do not tell the model to "end your answer".
- There is no wait tool.
- Parallel tool calls must stay free.
- If there is no other work, the model must do nothing.

## Work

Change these texts to the injection model. Use the same wording that Multitool uses. Agree the final wording with the session `foundationmodelsmultitool-a4` before you merge.

1. `Sources/FoundationModelsAgents/Tool/AgentsToolText.swift:131-133` — the pending text of `start agent`. Remove "End your answer now, or do other work first: its final message comes to you as a new message after your answer ends." Keep the `check agent` sentence only if the agreed wording keeps it.
2. `Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift:92-95` — the tool description. Remove "comes to you as a new message after you end your answer. Your answer is the text of your last turn, so give your final answer after you have the results of the agents that you started."
3. Update the tests that pin these texts:
   - `Tests/FoundationModelsAgentsTests/AgentsToolMountTests.swift:56-60` (`collectSentence`)
   - `Tests/FoundationModelsAgentsTests/AgentsToolDescriptionTests.swift:29-33`
4. Search for other "end your answer" / "answer ends" texts (sources, tests, docs, snapshots) and change them too.

## Text that the user approved

"This is not the result. When the work finishes, the session injects its result into this conversation as a new message. That message starts you working again, so you do not need to wait, to check, or to ask for it. Do not call a tool to wait or to check. If you have other work that does not need this result, do that work now. If no other work can be done until the result comes back, do nothing: write no text and call no tool. When the injected result arrives, continue the task from it."

Note: this text says "Do not call a tool to wait or to check". The current pending text tells the model to call `check agent`. Remove that call instruction from the pending text, or agree a different decision with the Multitool session.

## Acceptance criteria

- [x] No source, test, or doc text tells the model to "end your answer" or refers to "after your answer ends".
- [ ] The pending text of `start agent` and the tool description use the approved injection wording, the same as Multitool. (The approved wording is in. The confirmation with the session `foundationmodelsmultitool-a4` is still open. Multitool does not have the wording yet.)
- [x] The pending text does not tell the model to call a tool to wait or to check.
- [x] The tests pin the new texts, and all tests pass.

## Review Findings (2026-10-11 14:07)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 4 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/TheFinalMessage.md` — no validator matches this file

- [x] `Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift:93` `duplication/duplication` — The sentence that tells the model the session injects the run result is written twice in changed code. Here, inside the `fixedSentences` text, and again in `AgentsToolText.collectInstruction`. Both copies state the same rule: the result arrives as a new message, do not wait or check, and do nothing when no other work exists. A later wording fix to one copy could leave the other out of date, so the model would get two different instructions. Keep one constant for the injection-and-do-nothing sentences, for example in `AgentsToolText`, and build both `fixedSentences` and `collectInstruction` from it. The two texts differ only in their opening words, so the shared part can be one constant with the opening added per site. Update the tests to match the shared text.
- [x] `Sources/FoundationModelsAgents/Tool/AgentsToolText.swift:130` `duplication/duplication` — The same injection-and-do-nothing wording in `collectInstruction` repeats the sentences in `AgentsToolDescription.fixedSentences`. Both halves are inside this change, so this is a changed-set duplicate. The two copies can drift apart. Extract the shared injection sentences into one constant, as in the finding on AgentsToolDescription.swift:93, and use it from both `collectInstruction` and `fixedSentences`.

### Blocker (outside confirmation)

- [ ] The acceptance criterion "the same as Multitool" is not complete. A person must confirm the final wording with the session `foundationmodelsmultitool-a4`. The review did not do this check. Do not move this task to done until a person records this confirmation.