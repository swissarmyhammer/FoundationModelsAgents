---
assignees:
- claude-code
position_column: done
position_ordinal: ff8a80
title: The agents tool infers start agent for a call with no op, a prompt and an agent name
---
From the ACPAgent session (planner24 13710, seq 71). Twice, the model called `{"name": "planner", "agent": "planner", "prompt": "…"}` with no `op` and got "Unknown operation".

Fix: the agents tool's resolver now gets an inferOp hook (AgentsTool.inferredOp(of:)). A call whose fields are all `start agent` keys, with a prompt and an agent name, resolves to `start agent`. Any other op-less call keeps the unknown-op corrective. The two-agents conflict check also covers the inferred op. Tests: 4 new cases in ForgivingAgentNameTests. #bug