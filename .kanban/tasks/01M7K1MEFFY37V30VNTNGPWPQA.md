---
assignees:
- claude-code
position_column: done
position_ordinal: ff9f80
title: 'agents endpoint: the Agent type gives the display name of AGENT.md (TestudoApp D190)'
---
The `agents` GraphQL endpoint does not send the `name` key of AGENT.md. Thus the app shows the id (`default`), not the name (`Default`).

- `AgentDefinition.name`: the `name` key, or `nil` when the key holds no text. `AgentDefinition.displayName`: the name, or the id.
- `Agent.name: String!` on the endpoint gives `displayName`. `description` is already on the type.
- Tests: the default agent gives its display name; an agent with no `name` key gives its id; the golden schema has the field.