---
assignees:
- claude-code
depends_on:
- 01M7302JRZ9TWN09M5V08FZTZN
position_column: todo
position_ordinal: '8280'
title: 'AG-9: document the write operations of the agents tool'
---
## What
Write the documents for `add agent`, `edit agent`, `remove agent` and the `layer` option (D87, D175). Use Simplified Technical English.

- `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md`: a new section "Writing agents". It gives the three operations, the fields `name`, `content`, `document` and `layer`, the default `user`, the target folder of each layer (`<user layer root>/<id>/AGENT.md`, `<project layer root>/<id>/AGENT.md`; the project layer is the `.project` layer of the registry, in ACPAgent `<cwd of the session>/.agents/`), the reserved ids, the rule that `remove agent` deletes both forms of the agent in its layer, the cases that give no change event, the default agent (`default` is the root `AGENT.md`, edit only), the reload and the change event of the `agents` endpoint, and the rule that a defaults or marketplace layer is read-only.
- `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/LoadingTheCatalog.md`: one paragraph that says the tool writes into the user and project layers, and the registry reloads after each write.
- `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/FoundationModelsAgents.md`: add `AgentWriteLayer` to the topics.
- `README.md` and `docs/skills-and-agents.md`: add the three operations to each list of the operations of the `agents` tool.

## Acceptance Criteria
- [ ] Each document that lists the operations of the `agents` tool names `add agent`, `edit agent` and `remove agent`.
- [ ] The DocC catalog builds with no warning.

## Tests
- [ ] `swift package generate-documentation --target FoundationModelsAgents --warnings-as-errors` (or the DocC command that CI uses, see `Tests/FoundationModelsAgentsTests/CIWorkflowTests.swift`) passes.
- [ ] `swift test --filter ReadmeExampleTests` passes.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1 #AG-9