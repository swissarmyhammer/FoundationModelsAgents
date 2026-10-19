---
assignees:
- claude-code
position_column: done
position_ordinal: ed80
title: The name field of the agents schema is a plain string, checked against the live catalog at call time
---
## What
The `name` field of `AgentsToolSchema` is an enum of the agent names at make time (AgentsToolSchema.swift:80-85). An agent that a reload adds cannot be started in a running session, because constrained decoding refuses the name. SWE-bench run 2026-10-18: `coder` was added to the marketplace (skills 31ca028).

Make `name` always a plain string. `start agent` already checks the name against the live catalog and gives `AgentsToolText.unknownAgent` (AgentsToolText.swift:91).

- Remove `agentNames` from `AgentsTool` / `AgentsToolSchema.make` (or keep only for the description), and update the docs of `AgentsTool` (lines 15-21, 49-57, 101-104).
- The description still lists the agents at make time and stays byte-identical for the session.

## Tests (failing first)
- AgentsToolSchemaTests: the `name` field is a plain string schema with agents in the catalog.
- ReloadDuringRunTests: after a reload adds an agent, `start agent` with its name on the old tool starts it; a removed name gives the unknown-agent corrective.
- The description of the tool doesn't change after a reload.

## Acceptance
- [ ] Tests above pass, `swift test` green, no warnings. #agent-selection