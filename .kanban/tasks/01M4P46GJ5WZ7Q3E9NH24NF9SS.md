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