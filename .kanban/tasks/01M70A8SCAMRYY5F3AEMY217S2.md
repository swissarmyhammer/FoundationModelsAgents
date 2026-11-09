---
assignees:
- claude-code
depends_on:
- 01M70A8EVBG1S5T106BZA76RF6
- 01M70A8HFRP4W26Y4TEW8DCK0N
position_column: done
position_ordinal: ff8280
title: AgentRunner gives the instructions of the default agent for a host-built session
---
A host builds its main session from the default agent with no agent run. It needs the winning layered definition, its rendered body, and its `skills:` preload rendered through AgentSkillsPreload, with the same visibility check and warnings.

- `AgentRunner.defaultAgentInstructions() async throws(AgentRunFailure) -> DefaultAgentInstructions?`; nil when the catalog has no default agent.
- DefaultAgentInstructions: definition, body, skillBodies, diagnostics (the skill preload warnings), and `text` (body then skill bodies, joined as a run joins them). No AGENTS.md: the host adds those.
- `$ARGUMENTS` renders as empty text: there is no prompt yet.
- Tests: no default gives nil; layer precedence; preload in key order; unknown/hidden skill gives a warning and is skipped; the template context gates the body. #root-prompt