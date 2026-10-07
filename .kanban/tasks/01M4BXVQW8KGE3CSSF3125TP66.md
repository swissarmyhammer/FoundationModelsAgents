---
assignees:
- claude-code
depends_on:
- 01M4BXVEFR6J7MM3HRQFQX1D6K
- 01M4BY3TCN277D8K1RSM6X4ER6
- 01M4BY4BFX7BAHYQM55X3579CF
position_column: todo
position_ordinal: '8580'
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
- [ ] No document or doc comment says that only the final text comes back, that a run gets no follow-up, or that the tool has four operations.
- [ ] Each document that lists the ops of the `agents` tool names all six.
- [ ] The pinned rules `agentsToolRule` and `noToolsKeyRule` in `DocumentationTests.swift` state the new mount table.

## Tests
- [ ] Update `Tests/FoundationModelsAgentsTests/DocumentationTests.swift`:
  - the claims at :138-141 name each of the six ops on the tool article;
  - add a claim for the `parent` synonym;
  - change `agentsToolRule` and `noToolsKeyRule`;
  - add a check that no source or doc file has the text "four operations".
- [ ] Update `ReadmeExampleTests` for the `send agent` example.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.