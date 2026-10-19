---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5a864d6ynp4yxaa8a7h7q78
  text: |-
    Notice text agreed with foundationmodelsskills-28 (their task twxkgcw), 2026-10-19:

    ```
    The agents listed in the `agents` tool description have changed. These entries replace the listed ones:
    Added:
    - name: description
    Changed:
    - name: description
    Removed:
    - name
    ```
    One notice per reload with a visible change of this tool's startable set (model-visible, allowedNames, not the run's own agent). Changed = description changed; a body-only change posts nothing. Order Added, Changed, Removed; leave out an empty section; catalog order; full one-line description, never the cut one.
  timestamp: 2026-10-19T14:13:58.310356+00:00
position_column: todo
position_ordinal: '8380'
title: A reload that changes the startable catalog posts one catalog-change notice to each live session that has the agents tool
---
## What
`AgentsTool.make` reads the catalog one time (AgentsTool.swift:126-132). A running session never learns about an agent that a reload adds or removes. `AgentSearch` already follows `AgentRegistry.onReload` (AgentSearch.swift:128-134).

On each reload, compare the old and new startable catalogs of each live tool (its own `startableAgents()`: allowedNames, self rule). When they differ, post ONE catalog-change notice to that session, child sessions included. The notice names the added and removed agents (with descriptions of the added ones). The tool description doesn't change.

## Blocked
Use the shared notice type and the post seam of FoundationModelsExtras. The API is not on FoundationModelsExtras main yet (checked 2026-10-19); session foundationmodelsextras-8f has the design and sends it. Keep the text alike with FoundationModelsSkills (session foundationmodelsskills-28), which does the same for skills.

## Tests (failing first)
- A reload that adds an agent posts one notice to a live tool's session; a reload with the same startable catalog posts none; a child session's tool gets its own notice; the run's own agent is not announced to that run.

## Acceptance
- [ ] Tests pass, `swift test` green. #agent-selection #blocked