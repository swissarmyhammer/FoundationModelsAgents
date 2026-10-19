---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'The frontmatter key `enabled: false` turns an agent off: it is not startable, listed, found, or announced'
---
## What
Owner design item (relayed by foundationmodelsacpagent-a5, 2026-10-19): the frontmatter key `enabled: true|false`, default `true`, for skills, agents and rules. foundationmodelsextras-8f adds it to `FrontmatterDocumentStack`: a document gets `isEnabled`, and the stack gets an enabled-only view. The nearest layer wins: a nearer AGENT.md with `enabled: false` turns the agent off, also when a farther layer enables it.

Agents does not read through `FrontmatterDocumentStack` today. It has its own `AgentFrontmatter` decode (with the colon retry and `unsupportedKeys`) and its own layer scan (`AgentLayerScan`, `AgentCatalogBuilder`). Decide when the API lands: use the Extras `isEnabled`, or decode `enabled` in `AgentFrontmatter` with the same rule. A wrong type must fail closed (see the task "A frontmatter key of the wrong type fails closed").

Behaviour:
- `AgentsToolContext.canStart` / `startableAgents()` use only enabled agents. So the tool description list, `list agents`, `find agents` (the `AgentSearch` index) and `start agent` use only enabled agents.
- A disabled name gets the unknown-agent corrective (`AgentsToolText.unknownAgent`).
- A change of `enabled` reloads the catalog (the watcher already reloads on a file change) and posts the catalog-change notice (`AgentCatalogNotices`): disabling an agent → Removed, enabling it → New.
- Decide whether a disabled agent is still a slash command (`isUserInvocable`). Likely no.

## Blocked
Waiting for the Extras API from foundationmodelsextras-8f. It is not on FoundationModelsExtras main (39c9cde) as of 2026-10-19.

## Tests (failing first)
- Decode: `enabled: false` → disabled; no key → enabled; a wrong type → fails closed.
- Layer rule: a nearer `enabled: false` hides an agent that a farther layer enables.
- The tool: a disabled agent is not in the description, in `list agents` or in `find agents`; `start agent` with its name gives the unknown-agent corrective.
- Reload: switching `enabled` in a running session posts one notice (Removed, then New).

## Acceptance
- [ ] Builds against Extras, Router and Skills main; `swift test` green; tell foundationmodelsacpagent-a5 the sha. #agent-selection #blocked