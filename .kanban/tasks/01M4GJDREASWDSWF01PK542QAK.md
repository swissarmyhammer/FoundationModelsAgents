---
assignees:
- claude-code
depends_on:
- 01M4GJDD7QWN7A9SGK0FG50YED
position_column: todo
position_ordinal: '8180'
title: 'Load folder agents: agents/<name>/AGENT.md with resources'
---
## What

Change the agent format of this package from a single file `agents/<id>.md` to a folder `agents/<name>/AGENT.md`, symmetrical with skills (the user approved this on 2026-10-09). `AGENT.md` holds the YAML frontmatter and the body. The other files of the folder are the resources of the agent. The folder name is the agent id. This is a clean break (`feat!`): an old single file does not load.

Do this task after the plan.md and CLI removal is committed, and after the Extras change (depends on ^fg50yed) is in, so that the marketplace snapshot has the new shape.

## Changes

- `Registry/AgentCatalogBuilder.swift`: `agentFiles(in:)` finds each child folder of `agents/` in the combined view that holds `AGENT.md` (`plain.childDirectories` of `agents`, or the equivalent in `DotfolderStack`). The path is `agents/<id>/AGENT.md`. The highest layer that holds the path wins, and each lower copy gives one advisory, as now. Replace `fileSuffix` with a document name constant (use the Extras constant if it exists).
- A `.md` file directly in `agents/` gives one warning diagnostic that says to move it to `agents/<id>/AGENT.md`. It gives no agent. Add the diagnostic text to the place where the other diagnostic texts are.
- `Run/AgentBodyRenderer.swift:76`: `documentPath(of:)` gives `agents/<id>/AGENT.md`. Check that the partials search now also sees `agents/<id>/_partials/`, and test it.
- Resources: an agent folder can hold other files. Record the folder of the winning layer on `AgentDefinition` (or a URL to it) so that a later task can expose the resources. Do not add a resource operation in this task.
- `Examples/agent-library`: move each `agents/<id>.md` (defaults, user, project, broken, marketplace plugins) to `agents/<id>/AGENT.md`. Keep one old-format file in `broken/` to test the warning. A bad-name case moves to a bad folder name.
- Update all tests that write agent files (search `agents/` and `.md"` in Tests), the README, the DocC catalog, `docs/skills-and-agents.md`, and the doc comments that state `agents/<id>.md`.

## Acceptance criteria

- [ ] `agents/<name>/AGENT.md` loads, and its id is the folder name.
- [ ] A higher layer folder hides a lower one, with one advisory.
- [ ] An old `agents/<id>.md` file gives one warning and no agent.
- [ ] A partial in the agent folder renders.
- [ ] Marketplace end-to-end tests pass with the new snapshot shape.
- [ ] `rg 'agents/<id>\.md|agents/[a-z-]+\.md'` finds no old-format text, except the deliberate broken fixture and its test.
- [ ] `swift build` and `swift test` pass with no warnings.