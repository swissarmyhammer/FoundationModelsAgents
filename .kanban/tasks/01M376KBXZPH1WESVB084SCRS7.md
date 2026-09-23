---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m387ce1y54bm2hw0rprc67gr
  text: |-
    Research and implementation notes:
    - The library needed no change. Each case of the card passes on the current code.
    - `FixtureMarketplaceProvider.make(select:)` and `makeUnstarted(select:)` now take a `SkillSelection` (default `.all`). `fixtureTree()` is internal, so a test can commit the fixture tree again with one more file.
    - A new commit plus `market.fixture.store.update()` swaps the snapshot at the stable layer root and sends `layerUpdates`. Keep the `Unstarted` value alive to the end of the test, because it holds the `GitFixtureRepository`.
    - A tree source (no `.claude-plugin/marketplace.json`) with `agents/x.md`, `_partials/p.md`, and `skills/s/SKILL.md` gives the layer `agents/x.md`, `_partials/p.md`, `s/SKILL.md`. An agent body of that layer includes the root partial. The §16 shape is confirmed for a catalog source and a tree source.
    - `.plugins(["code-tools"])` gives security-reviewer only. `.skills(["review"])` gives one layer, the skill, and no agents.
    - The reload test of the tool moved from `AgentsToolOperationsTests` to `ReloadDuringRunTests` (no duplicate). `AgentsToolSchemaTests.property(named:in:)` and `nameFieldName` are internal now, so the reload test reads the `name` enum of the old schema.
    - A static stored dictionary of `GitFixtureRepository.Entry` does not compile under Swift 6 (not Sendable). Use a static func.
  timestamp: 2026-09-23T22:50:03.710451+00:00
- actor: claude-code
  id: 01m387cgq1xmassx3bmnbkqtyd
  text: |-
    ### implement — changed
    - evidence: 5 files — Tests/FoundationModelsAgentsTests/MarketplaceEndToEndTests.swift (new), Tests/FoundationModelsAgentsTests/ReloadDuringRunTests.swift (new), Tests/FoundationModelsAgentsTests/Support/FixtureMarketplaceProvider.swift, Tests/FoundationModelsAgentsTests/AgentsToolOperationsTests.swift, Tests/FoundationModelsAgentsTests/AgentsToolSchemaTests.swift. `swift test --filter "MarketplaceEndToEndTests|ReloadDuringRunTests|AgentsToolOperationsTests|AgentsToolSchemaTests|AgentRegistryMarketplaceTests"`: 40 tests in 5 suites pass. swiftlint: 0 violations.
    - next: test
  timestamp: 2026-09-23T22:50:06.433193+00:00
- actor: claude-code
  id: 01m387p522g780403z0yc29tfp
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 290 tests in 40 suites pass, 0 failed, 0 skipped, no warnings; `swiftlint lint --quiet Sources Tests Examples` — 0 violations.
    - next: commit
  timestamp: 2026-09-23T22:55:22.178747+00:00
- actor: claude-code
  id: 01m387phqb62t33bk0mqm5mmx9
  text: |-
    ### commit — changed
    - evidence: 4101b2c test(marketplace): marketplace agents end to end over a git source; reload during a run
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T22:55:35.147871+00:00
- actor: claude-code
  id: 01m3882qj65vbnvrv7y879prte
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 0 confirmed, 1 refuted; 5 files reviewed (.kanban excluded by .reviewignore).
    - next: done

    ### finish iteration 1 — clean
    - implement: changed (5 test files; no library change needed)
    - test: green (290 tests in 40 suites, 0 failed, 0 skipped; swiftlint 0)
    - commit: changed (4101b2c)
    - review: clean (0 findings)
  timestamp: 2026-09-23T23:02:14.342734+00:00
depends_on:
- 01M376XK8GJY5DVQ66492JW7TT
- 01M376FT1NDWQF9SG4D3XDESSM
- 01M376J7SAXPM4H7MP8NYTAV8F
- 01M376H7W3JTVB6X8M5GBDQNNN
position_column: done
position_ordinal: 9b80
title: Marketplace agents end to end with a git source; reload during a run
---
## What
Plan.md §6, §14 M7, and the reload cases of §15. Hermetic: a real `MarketplaceStore` over a local git fixture from `MarketplaceFixtures` (`GitFixtureRepository`), and the scripted profile.

- Create `Tests/FoundationModelsAgentsTests/MarketplaceEndToEndTests.swift`:
  - Commit `Examples/agent-library/marketplace` into a fixture git repository; make a `MarketplaceStore` with it as a source and `.all`; one store feeds a `SkillsRegistry` and an `AgentRegistry`.
  - Selection `.plugins(["code-tools"])` gives `security-reviewer` only; `.skills([...])` gives no agents.
  - An agent body of the plugin includes `house-rules.md` from `<layer root>/_partials/`.
  - A `skills:` preload of a skill of its own plugin works.
  - A `model: sonnet` marketplace file warns and runs on `inherit`.
  - A new commit and a store update give a new catalog through `layerUpdates`.
- Create `Tests/FoundationModelsAgentsTests/ReloadDuringRunTests.swift`:
  - A run in operation keeps its definition after the file changes.
  - A tool made before a reload: a changed agent runs with the new definition; a removed agent gives the corrective with the current names; an added agent is in `list agents` and not in the old schema.
- Verify (plan.md §16): the Extras layer has the §6.1 shape for a catalog source and for a tree source, with the partials at `<snapshot>/_partials/`.
- Fix defects in the library that these tests find; do not change Extras from this task (raise a task in Extras if Extras is wrong).

## Acceptance Criteria
- [x] Each case above passes.
- [x] No test needs the network.

## Tests
- [x] The two test files above.
- [x] Run `swift test --filter "MarketplaceEndToEndTests|ReloadDuringRunTests"`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.