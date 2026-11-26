---
assignees:
- claude-code
position_column: done
position_ordinal: ffa180
title: 'agents endpoint: the Agent type gives the absolute path of its AGENT.md (TestudoApp ^gnk3rh8)'
---
## Problem

The inspector of Testudo shows the file of an agent, with Reveal in Finder. The `Agent` type of the `agents` endpoint gives `layer { name root }` and `marketplace { id sha }`, but no path of the file. The file can be `<root>/<id>/AGENT.md`, `<root>/agents/<id>/AGENT.md` or `<root>/AGENT.md`. Thus the app cannot compute the path.

## Work

- Add `path: String!` to the `Agent` type: the absolute path of the AGENT.md of the entry, `AgentDefinition.url.path`. It is the file of the layer that gave the agent, for each layer, marketplace entries included.
- Update the golden schema file `Tests/Fixtures/agents.graphql`.

## Acceptance

- An agent in the agent folder form gives `<root>/<id>/AGENT.md`.
- The default agent gives `<root>/AGENT.md`.
- A marketplace agent gives `<marketplace root>/agents/<id>/AGENT.md`, and the file exists.
- `swift test` passes.

After the push, send the sha to TestudoApp. #feature