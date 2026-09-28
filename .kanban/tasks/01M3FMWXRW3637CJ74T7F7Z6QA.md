---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3myzce42z5hp62qdsfy47yt
  text: |-
    Research. The old run model is in these places:
    - plan.md: §1 (a run posts; generation), §5 maxTurns (delivery and final-answer turns), §7 table (two slots share a model; the Router refuses one model for two slots; the part before `@` gives `standard` for one repository at two revisions), §8 steps 6-8, §9.1 description quote and the `start agent` and `check agent` rows, §9.2, §9.3 (generation gate, child-delivery turn, maxTurns, cancelRuns posts), §9.4 (no post), §12 sketch (dispatchNextPrompt), §15 tool and runs bullets, §15 full circle, §16 verify list.
    - DocC: TheFinalMessage.md (post, stage, dispatchNextPrompt, delivery and final-answer turns), RunningAnAgent.md (delivery and final-answer turns, maxTurns), DelegatingWithTheAgentsTool.md (start agent row, delivery turn).
    - README.md is already correct (mail from the pump); no change needed there except as found.
    - Sources: AgentsToolText.collectInstruction ("When it is an agent" is from the whole-tool mount); AgentsToolDescription fixed sentences ("comes to you as a tool result"); AgentRunProgress phase text "a delivery turn"; AgentRunner doc comments (child-delivery turn, final-answer turn, run posts its final message); AgentsCLI and AgentsCLIOperations ("posts nothing").
    - delegationSentence belongs to ^p3ww0ar, and the §4.2 table and the §9.3 example belong to ^rawqayy. This task does not change them.
  timestamp: 2026-09-28T21:33:15.076783+00:00
- actor: claude-code
  id: 01m3n1r8g2fmchg77e2mz2sk9n
  text: |-
    Implementation.
    - RED first: DocumentationTests got the claims "`start agent` is a background run.", "The final message comes to the calling session as mail.", "The pump of the Router delivers the mail.", and "A run ends when its session is idle." (the `dispatchNextPrompt()` claim is gone). A new suite RunModelWordingTests holds plan.md, README.md, docs/skills-and-agents.md, each DocC page, and each line of Sources/ to no text of the removed model (dispatchNextPrompt, enqueue(prompt:), cancelCurrentTurn, delivery turn, final-answer, inlineSettleGrace, posts its final message, generation gate). AgentsToolMountTests pins the `next` sentence of the pending envelope. The RED run failed for the expected reasons (36 issues).
    - Tool text: the `next` sentence now says "This agent works in the background. Do not wait for it, and never guess its result. End your answer now, or do other work first: its final message comes to you as a new message after your answer ends." The description fixed sentences say the final message comes "as a new message after you end your answer" (not "as a tool result"). The delegation sentence is not changed; it belongs to ^p3ww0ar.
    - The check agent phase text "a delivery turn" is now "an answer to a final message", and the case `AgentRunPhase.delivery` is now `.answeringMail`.
    - plan.md: §1, §5 maxTurns, §7 table (the Router gives the two slots two models; the part before `@` gives `standard` for one repository at two revisions), §8 steps 6-8, §9.1 (mount of each operation, the envelope sentence, rows), §9.2 (rewritten), §9.3, §9.4, §12 sketch, §14 M4 and M5, §15, §16.
    - DocC: TheFinalMessage, RunningAnAgent, DelegatingWithTheAgentsTool. README needed no change.
    - Also corrected "generation gate ... for the whole turn" comments in Tests, IntegrationTests and Examples: the Router runs each submission as one item of the generation queue of its model (Router SessionLanguageModel.swift).
    - Notes: SwiftPM prints "failed loading cached manifest ... disk I/O error" warnings; these are cache warnings of the host, not compiler warnings. The CallingRun test play still has two `.finalTextOfLaterPrompts` steps; the second one is not used now, and the test passes.
  timestamp: 2026-09-28T22:21:47.394593+00:00
- actor: claude-code
  id: 01m3n1rdy59mjk8982b5d94thz
  text: |-
    ### implement — changed
    - evidence: 26 files — plan.md; Sources/FoundationModelsAgents/FoundationModelsAgents.docc/{TheFinalMessage,RunningAnAgent,DelegatingWithTheAgentsTool}.md; Sources/FoundationModelsAgents/Tool/{AgentsToolText,AgentsToolDescription,AgentsTool}.swift; Sources/FoundationModelsAgents/Run/{AgentRunProgress,AgentRun+Children,AgentRunner}.swift; Sources/FoundationModelsAgents/CLI/{AgentsCLI,AgentsCLIOperations}.swift; Tests/FoundationModelsAgentsTests/{DocumentationTests,RunModelWordingTests (new),AgentsToolMountTests,AgentsToolDescriptionTests,AgentRunProgressTests,CheckAgentProgressTests,AgentSchedulingTests,AgentSchedulingTests+CallingRun,Support/ScriptedAgentModel}.swift; IntegrationTests/Tests/AgentsIntegrationTests/{LiveSlotTests,LiveNestedTests,Support/LiveTools,Support/LiveHarness,Support/LiveProfile}.swift (comments only); Examples/agents-demo/AgentsDemoProfile.swift (comments only). `swift build -Xswiftc -warnings-as-errors`: Build complete. `swift test -Xswiftc -warnings-as-errors`: 382 tests in 53 suites passed. swiftlint: 0 violations. Not committed.
    - next: /review
  timestamp: 2026-09-28T22:21:52.965455+00:00
depends_on:
- 01M3A6EGTPK2A08N066GGPYAEM
position_column: doing
position_ordinal: '80'
title: 'Documents for background runs: plan §8 and §9, the README, TheFinalMessage and the tool text'
---
## What
State the run model of ^ggpyaem in every document. Plans state intent, not history.
- `plan.md` §8 (a run and its session), §9 (the `agents` tool, the final message, delivery), and every place that names `dispatchNextPrompt()`, delivery turns, or the final-answer prompt (the research found lines near 355, 362-363, 483, 491, 662, 826). New text: `start agent` is a background run; the final message is the run detail and comes to the parent as mail; the Router pump delivers it; a run ends when its session is idle; `maxTurns` counts passes from the live events.
- `README.md` (near lines 135 and 159), `FoundationModelsAgents.docc/TheFinalMessage.md` (near 45, 52, 57), `DelegatingWithTheAgentsTool.md`, `RunningAnAgent.md`.
- `Tool/AgentsToolText.swift`: the text for `start agent` agrees with the Router pending envelope. The model must end its answer to receive the mail.
- `Tests/FoundationModelsAgentsTests/DocumentationTests.swift`: replace the claim that names `dispatchNextPrompt()` (near line 132) with claims for the new model.
- Doc comments in `Run/AgentRunProgress.swift`, `Run/AgentRun*.swift` that name the removed driver or delivery turns.

## Acceptance Criteria
- [x] No document or doc comment names `dispatchNextPrompt`, `enqueue(prompt:)`, `cancelCurrentTurn`, delivery turns, or the final-answer prompt.
- [x] `DocumentationTests` holds claims for: a background run, mail delivery, and the idle rule.

## Tests
- [x] Update `DocumentationTests.swift` first and see the new claims fail.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.