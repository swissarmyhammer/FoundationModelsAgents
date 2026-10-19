---
assignees:
- claude-code
position_column: done
position_ordinal: ee80
title: 'The fixed sentences of the agents description state the delegation rule: a whole unit of work to an agent, a one-step task yourself, commit often'
---
## What
SWE-bench run 2026-10-18: across 16 Django instances the model made 2 `agents` calls and started no agent. `matchSentences` (AgentsToolDescription.swift:78-84) says to compare each task with each description, which is a weak rule.

Replace it with a delegation rule in the fixed sentences:
- Give an agent a whole unit of work: one that needs many reads, a long output, or a fix-and-test loop.
- Do a one-step task yourself.
- Pick the agent whose description matches the work; `list agents` when the list is cut or none matches.
- Tell the agent in the prompt to commit often, so each commit is an undo point (the owner wants this).

Keep: the empty-context sentence, the delegation sentence, the pending-work instruction, the self rule (the run's own agent isn't listed). The fixed sentences don't count against the list limit.

## Tests (failing first)
- AgentsToolDescriptionTests: the fixed sentences contain the unit-of-work rule, the one-step rule, and the commit-often sentence. Update exact-text expectations.

## Acceptance
- [ ] Tests pass, `swift test` green; docs (`DelegatingWithTheAgentsTool.md`) match the new text. #agent-selection