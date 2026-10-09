---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gwnembr2axmz7p7fdgga8k
  text: |-
    Research and decisions:
    - The loader uses `childDirectories(of: "agents")` and `exists("agents/<id>/AGENT.md")` per layer. `MarketplaceLayer.agentDocumentName` from Extras is the document name. `AgentCatalogBuilder.documentPath(of:)` is shared with `AgentBodyRenderer`.
    - Old format: each `.md` file directly in `agents/` of each layer gives one warning (one for each file, in each layer). The search uses `DotfolderStack.urls`, so it reads no text. The warnings come after the diagnostics of the agent folders. Text: "the file 'agents/<n>.md' has the old agent format and does not load; move it to 'agents/<n>/AGENT.md'". The text is in `AgentDefinitionRules.oldFormatFinding`.
    - Resources: `AgentDefinition.folderURL` (public, computed from `provenance.url`) is the agent folder of the winning layer.
    - Partials: the render document path is now `agents/<id>/AGENT.md`, so the include search finds `agents/<id>/_partials/` first. Before this fix the test failed (RED); after the fix it passed.
    - The texts for the id rules now say "folder name" in place of "file name".
    - Build problem: the working tree of `../FoundationModelsExtras` held uncommitted ^77e7ynm changes, and the pinned FoundationModelsSkills checkout (2b3695c) did not compile against them. `swift package update FoundationModelsSkills` moved the checkout to remote main 53a9201, and Package.resolved did not change. The `swift package edit` now points at `../FoundationModelsExtras` (f7095e5).
  timestamp: 2026-10-09T17:51:36.587052+00:00
- actor: claude-code
  id: 01m4gxrbvwgj5b9v8wtbwtey75
  text: "### implement — changed\n- evidence: `swift build` is clean. `swift test` passed 487 tests in 65 suites with 0 failures. The only warning is the SwiftPM build-system note \"missing creator for mutated node … mlx-swift_Cmlx.bundle\". It comes from the mlx dependency and was there before this change. `swift run agents-demo --marketplace` lists 7 agents: doc-writer and security-reviewer from the marketplace, and 5 from local layers.\n- Files changed: \n  - Sources: AgentCatalogBuilder, AgentDefinitionRules, AgentDefinition (`folderURL`), AgentBodyRenderer, AgentRegistry, plus doc comments in AgentCatalog, AgentListing, AgentDiagnostic, AgentFrontmatter, FoundationModelsAgents.swift and DocC.\n  - Fixtures: every agents/<id>.md moved to agents/<id>/AGENT.md. New files: broken/agents/old-format.md and the resource security-reviewer/checklist.md. marketplace.json is deleted.\n  - Tests: 28 files, plus the new Support/AgentDocumentPath.swift.\n  - Other: README, docs/skills-and-agents.md, agents-demo comment, IntegrationTests Support (LiveAgentFile, LiveSourceTree).\n- Acceptance search: the remaining hits for `agents/<id>.md` are deliberate (the old-format test and the `oldFormatSuffix` doc). FixtureLibraryTests checks that `.claude-plugin/marketplace.json` is absent.\n- open: `swift build --package-path IntegrationTests` fails because that package uses the remote Extras main, which does not have `agentDocumentName` yet. It will build after the Extras commits are pushed.\n- next: /review"
  timestamp: 2026-10-09T18:10:40.636252+00:00
- actor: claude-code
  id: 01m4h954h6j4x43zf1v518sq4d
  text: |-
    ### review — findings
    - evidence: `review working`, 1 finding (1 confirmed, 1 refuted) — IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveAgentFile.swift:56 (reuse/reuse). The rule 'code-hygiene/dead-code-swift' failed because SwiftPM could not remove the checkouts in `.build/checkouts` (FoundationModelsRouter, FoundationModelsExtras: "Operation not permitted"). Its findings are missing.
    - next: correct the finding, then run /review again after the `.build` folder is repaired, so that the dead-code rule runs.
  timestamp: 2026-10-09T21:29:53.446178+00:00
- actor: claude-code
  id: 01m4hadp90yhg0jh0mrkvryzas
  text: |-
    ### review fix — changed
    - evidence: the finding at IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveAgentFile.swift:56 is fixed. `path(of:)` now uses `MarketplaceLayer.agentsDirectoryName` and `MarketplaceLayer.agentDocumentName`; the local constants are removed. Against GitHub main (Extras 5bc870a, Skills 53a9201, Router 16abef2): `swift build --build-tests` passes, `swift test` passes 487 tests in 65 suites, `swift build --package-path IntegrationTests --build-tests` passes.
    - next: commit.
  timestamp: 2026-10-09T21:52:02.337+00:00
depends_on:
- 01M4GJDD7QWN7A9SGK0FG50YED
position_column: done
position_ordinal: cd80
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

## Review Findings (2026-10-09 16:12)

> Scope: `review working` — reviewed the diffs only — lines this change added or modified. 39 file(s) reviewed, 41 not reviewed.

> Not reviewed: 4 files in `.kanban/` (excluded by `.reviewignore`). 37 files had no matching validator: the `Examples/agent-library` fixtures, `README.md`, the two DocC `.md` files, and `docs/skills-and-agents.md`.

> Warning: tool rule 'code-hygiene/dead-code-swift' failed — the tool judged nothing, so its findings are missing. The cause: SwiftPM could not remove `.build/checkouts/FoundationModelsRouter` and `.build/checkouts/FoundationModelsExtras` ("Operation not permitted"). Run this rule again after the `.build` folder is repaired.

- [ ] `IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveAgentFile.swift:56` `reuse/reuse` — The new path(of:) builds agents/<id>/AGENT.md by hand. The library already builds the same path in AgentCatalogBuilder.documentPath(of:), and the test support has AgentDocumentPath.of. Each copy is a separate place to fix if the layout changes. Build the path from MarketplaceLayer.agentsDirectoryName and MarketplaceLayer.agentDocumentName, the same constants the library uses. Keep it local only if the integration target cannot import those public names, and say so in a comment.