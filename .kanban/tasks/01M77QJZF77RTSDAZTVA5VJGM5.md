---
assignees:
- claude-code
position_column: done
position_ordinal: ff9680
title: tools.agents.enabled is false in the body of an agent with disallowedTools [agents]
---
Seen in oneplan24: the house-rules partial gate `{% if tools.agents.enabled %}` (schedule agent) rendered in planner and double-check, which have `disallowedTools: [agents]`, because AgentBodyRenderer renders each body with the session templateContext of the registry. The renderer turns tools.agents.enabled off for an agent whose selection denies the agents tool; other groups stay as the host gave them (their tools are the host's, e.g. inside runCode). Test first: AgentToolTemplateTests.