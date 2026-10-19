---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5abfgfjd2wah9520dmn8y9v
  text: |-
    Decisions from foundationmodelsacpagent-a5 (2026-10-19):
    1. Wrong value type for `enabled`: fail closed (the agent is off), with one diagnostic. Extras uses the same rule for skills and rules.
    2. Do not write a second decode of the key. Extras exposes the decode and the value rule of `enabled` as a reusable piece; use it. The nearest-layer rule stays in our own scan (AgentLayerScan / AgentCatalogBuilder; the file read is FrontmatterDocumentStack.readDocument at AgentCatalogBuilder.swift:268): the nearest copy wins, and if it is disabled the agent is off — a farther copy does not come back.
    3. A disabled agent is not a slash command either. Disabled = gone from every model and user surface, except a settings or diagnostic listing (runner.catalog() diagnostics / listings may still show it as disabled).
    Still blocked on the Extras piece.
  timestamp: 2026-10-19T15:11:31.314259+00:00
position_column: done
position_ordinal: f180
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