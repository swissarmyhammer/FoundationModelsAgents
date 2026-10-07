---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4ccbczmgqeart3g81cs8p62
  text: |-
    Research done. Facts from the code:
    - Tool ops: list agents, start agent, check agent, cancel agent, send agent, send caller. Noun alias `parent` -> `caller` (AgentsTool.nounAliases). Only `start agent` is background.
    - Mount table: AgentSessionMaker.mountedGrant. An `Agent` entry below maxDepth -> full grant. Else a run with a caller -> messagingOnly. Else no tool. A `disallowedTools` deny wins (ToolResolver.resolve does not ask for a grant). No `tools` key gives no Agent grant, thus a run with a caller gets only the message ops.
    - Correctives: runEnded "The run <id> ended (<state>), and it gets no more messages. Start a new run."; noCaller "You have no caller.".
    - AgentRun.deliver holds a message until the run reads the start of the task answer (CallerMessageGate).
    - Child messages: SessionEvent.runMessage; ParentSessionWatch keeps them; the idle rule requires an answered prompt for each.
    - Telemetry: agent.message.sent, direction to_run / to_caller, outcome delivered / ended / no_caller, length only.
    - CLI: five commands; `agent send`; no command for send caller.
    - Code doc comments (AgentsTool.swift, AgentsToolContext.swift, AgentsToolOperations.swift) already name all six ops. "four operations" stays in: FoundationModelsAgents.swift, README, DocC tool article (wrapped over two lines), plan.md (§1, §3, §9.4, M4), AgentsToolOperationsTests doc comment.
    - Text that is now false: RunningAnAgent.md "Nothing goes to the caller during the answer.", plan §8 step 6 same, plan §9.2 "The run gives nothing to the caller while it works", plan §9.3 depth bullet ("A run at maxDepth gets no agents tool"), docs "the caller gets only the final text of the run".
    - README send example plan: a second Swift block that uses `AgentsCLI` `agent send`, with its own marker pair in ReadmeExampleSource, so the test can gate the run and make the send deterministic.
  timestamp: 2026-10-07T23:49:32.276586+00:00
- actor: claude-code
  id: 01m4ccpfxsygn9mzya05vpf1kd
  text: |-
    Implementation landed.
    - RED: `swift test --filter 'DocumentationTests|ReadmeExampleTests'` failed with 9 issues for the expected reasons: the new claims were missing, "four operations" was in the files, and the README had no block for the send copy.
    - GREEN: the same filter plus DocsTests, ReadmeTextTests and RunModelWordingTests ran 28 tests in 5 suites and all passed. Full `swift test` ran 501 tests in 68 suites and all passed.
    - The README send example is a second Swift block (`AgentsCLI` `agent send`). Its compiled copy is `ReadmeExampleSource.send(runner:run:)`, which has its own marker pair. The test holds the run at a ScriptedGate, thus the send always reaches a run in operation. When the send copy was in the main example, the result depended on time, because the scripted task answer can end the run before the send.
    - New test `eachCompiledCopyIsAReadmeBlock` checks the other direction: each marker copy must be a README block. `ReadmeExample.copies(in:)` and `code(of:)` are new test helpers.
    - The "four operations" check reads each Swift and Markdown file under Sources/ and docs/, plus README.md and plan.md. It reads each run of white space as one space, because the DocC page split the words over two lines.
    - The doc comments of AgentsTool.swift, AgentsToolContext.swift and AgentsToolOperations.swift already named all six ops. Only FoundationModelsAgents.swift had the old count.
    - A build warning comes from SwiftPM and not from the code: "missing creator for mutated node ... mlx-swift_Cmlx.bundle". It is in the mlx bundle of .build.
  timestamp: 2026-10-07T23:55:35.737746+00:00
- actor: claude-code
  id: 01m4ccpmsykhdy3fverntpgq9r
  text: |-
    ### implement — changed
    - evidence: 13 files — plan.md, README.md, docs/skills-and-agents.md, Sources/FoundationModelsAgents/FoundationModelsAgents.swift, Sources/FoundationModelsAgents/FoundationModelsAgents.docc/{DelegatingWithTheAgentsTool,TheFinalMessage,RunningAnAgent,FoundationModelsAgents}.md, Tests/FoundationModelsAgentsTests/{DocumentationTests,ReadmeExampleTests,ReadmeExampleSource,AgentsToolOperationsTests}.swift, Tests/FoundationModelsAgentsTests/Support/ReadmeExample.swift. `swift test`: 501 tests in 68 suites passed.
    - note: the time dependence of a send in the main README example comes from a reading of the code. No test run showed it.
    - next: /review
  timestamp: 2026-10-07T23:55:40.734630+00:00
depends_on:
- 01M4BXVEFR6J7MM3HRQFQX1D6K
- 01M4BY3TCN277D8K1RSM6X4ER6
- 01M4BY4BFX7BAHYQM55X3579CF
position_column: doing
position_ordinal: '80'
title: 'Documents: messages between a run and its caller'
---
## What
The documents must agree with these changes:
- the new operations `send agent` and `send caller` (alias `send parent`);
- the messaging tool that each run with a caller gets.

Files:
- `plan.md`:
  - :38-49: replace "A run gives one final message, as mail" with this rule: a run can send messages to its caller while it works, and it gives one final message when it ends.
  - Replace "Only its final text comes back" and "No follow-up into a finished run" with this rule: a caller can send a message to a run that is still running. A run that ended gets no message, and the call gives a corrective.
  - §9.1 (table at :487): add `send agent`, `send caller`, and the `parent` noun synonym.
  - §9.2 (:516-531): message mail starts an answer the same as a final message. `mailOnlyAnswerLimit` and `mailDeliveryPaused` apply to it.
  - §9.3: the mount table of the messaging tool.
  - §9.4: `agents agent send`.
  - Change "four operations" at :91, :616 and :775.
- Doc comments that say "four operations": `Sources/FoundationModelsAgents/Tool/AgentsTool.swift`, `Tool/AgentsToolContext.swift`, `Tool/AgentsToolOperations.swift`, `Sources/FoundationModelsAgents/FoundationModelsAgents.swift`.
- DocC:
  - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md`: the six ops, with one example of each new op.
  - `TheFinalMessage.md`: messages before the final message.
  - `FoundationModelsAgents.md`: "four operations".
- `README.md` :15-18: the op list. Add a `send agent` example in a form that `ReadmeExampleTests` checks.
- `docs/skills-and-agents.md`: the access rule. Each run with a caller can send messages to it.

## Acceptance Criteria
- [x] No document or doc comment says that only the final text comes back, that a run gets no follow-up, or that the tool has four operations.
- [x] Each document that lists the ops of the `agents` tool names all six.
- [x] The pinned rules `agentsToolRule` and `noToolsKeyRule` in `DocumentationTests.swift` state the new mount table.

## Tests
- [x] Update `Tests/FoundationModelsAgentsTests/DocumentationTests.swift`:
  - the claims at :138-141 name each of the six ops on the tool article;
  - add a claim for the `parent` synonym;
  - change `agentsToolRule` and `noToolsKeyRule`;
  - add a check that no source or doc file has the text "four operations".
- [x] Update `ReadmeExampleTests` for the `send agent` example.
- [x] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.