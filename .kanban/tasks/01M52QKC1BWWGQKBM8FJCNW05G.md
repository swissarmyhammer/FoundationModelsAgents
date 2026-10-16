---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m52yqww9vwcksgh1gm0dxh92
  text: |-
    Research done (implement step).

    - The selection parts are public and usable. `import FoundationModelsSkills` re-exports FoundationModelsMetadataRegistry (SeamReexports.swift): `MetadataSearcher<Item: SearchableMetadata>`, `MetadataIndex`, `SearchMode`, `SelectionConfig`, `PooledEmbedding`. `SkillsTool.make(registry:model:)` builds a `.auto` searcher with `SelectionConfig(model:)` plus a `.retrieval` fallback searcher. `SkillSearchAgent` and `SkillsReloadFollower` are typed to `SkillMetadata`, thus the agents search uses the generic `MetadataSearcher` with an agent row type (`SearchableMetadata`), not a copy of the engine.
    - `skillsSelectionModel` is a parameter of `AgentEnvironment.make` only; the environment does not keep it. The plan keeps it on the environment, and `find agents` uses the same model.
    - The embedding: `LanguageModelProfile.embedding` (`RoutedEmbedder`) has `embed(texts:)` but does not conform to `PooledEmbedding`. A small adapter gives it to the searcher. The scripted test profile embeds each text as one constant vector.
    - `AgentRegistry.onReload` gives each catalog after the access (load, reload, watcher). The plan: one search per `AgentRunner`, seeded from `registry.catalog()` after the subscription, with a follower task that calls `MetadataSearcher.update(items:)` for each catalog. The rows hold only `isModelVisible` agents. The operation then keeps only the agents that the tool can start (`startableAgents()`).
    - Pinned tests that change with a new op: AgentsToolSchemaTests (op enum, parameters, properties) and DocumentationTests (toolOperations list). The DocC page says "six operations".
    - A deterministic reload test: a test embedder that signals the texts that `update(items:)` embeds. `update` swaps the index before it embeds, thus the signal tells that the new index is in place. No wall-clock wait.
  timestamp: 2026-10-16T18:14:13.641792+00:00
- actor: claude-code
  id: 01m52z9jj2ts10rbdqbc7jazxe
  text: |-
    Implementation landed (not committed).

    - New `Tool/AgentSearch.swift`: `AgentSearchEntry` (a `SearchableMetadata` row of id and description; `init?` gives nil for an agent that is not model-visible), `ProfileEmbedding` (adapter from `LanguageModelProfile.embedding` to `PooledEmbedding`), and `AgentSearch` (one `MetadataSearcher` in `.auto` mode with `SelectionConfig(model:)`, plus a `.retrieval` fallback searcher, over one `MetadataIndex`; this is the assembly of `SkillsTool.make(registry:model:)`). With no selection model, one `.retrieval` searcher. The init subscribes to `onReload` before it reads the seed catalog; one stored task gives each catalog to `update(items:)`, and `deinit` cancels it.
    - The fallback (selection throws, not a cancellation, then the retrieval searcher ranks) is about six lines in `AgentSearch.search`. `SkillSearchAgent` and `SkillsReloadFollower` are typed to `SkillMetadata`, thus they cannot take agent rows. The engine (BM25, trigram, cosine, selection tier) is not copied.
    - `AgentEnvironment` keeps `selectionModel` (the `skillsSelectionModel` of `make`); the internal init has a defaulted `selectionModel:` parameter, thus the test harness needed no change.
    - `AgentRunner.agentSearch`: one index for each runner.
    - `FindAgents` op (`query`, `limit?`, default 5) after `list agents`. It searches with the catalog count as the limit, keeps only `startableAgents()`, then cuts to `limit`. Correctives: blank query, limit below one. `AgentsToolText.listing(of:)` is now the one listing text of `list agents` and `find agents`.
    - Docs: `docs/skills-and-agents.md` (the `search skill` row now says "Replaced by D61", and a new "Find an agent" section), DocC `DelegatingWithTheAgentsTool.md` (seven operations, table row, "Find an agent" section, correctives, synchronous list), DocC landing page, README, namespace doc, Package.swift comment.
    - Tests: new `FindAgentsTests` (10 tests); `SelectionProbeModel` can now give an answer text; new `SignalingEmbedder` support. The reload row waits on the embed batch of the new agent, not on a clock. Pinned tests updated: AgentsToolSchemaTests, DocumentationTests (toolOperations), DocsTests (claim of the D61 row).
  timestamp: 2026-10-16T18:23:52.898108+00:00
- actor: claude-code
  id: 01m52z9sqte2pc6c8t2bb8sqss
  text: |-
    ### implement — changed
    - evidence: 21 files. New: Sources/FoundationModelsAgents/Tool/AgentSearch.swift, Tests/FoundationModelsAgentsTests/FindAgentsTests.swift, Tests/FoundationModelsAgentsTests/Support/SignalingEmbedder.swift. Changed: Run/AgentEnvironment.swift, Run/AgentRunner.swift, Tool/AgentsTool.swift, Tool/AgentsToolOperations.swift, Tool/AgentsToolText.swift, FoundationModelsAgents.swift, docc/DelegatingWithTheAgentsTool.md, docc/FoundationModelsAgents.md, docs/skills-and-agents.md, README.md, Package.swift (comment), Tests AgentsToolSchemaTests, DocsTests, DocumentationTests, Support/SelectionProbeModel.swift. `swift build --build-tests`: clean (only the accepted mlx-swift "missing creator" line). RED seen first (compile errors for the missing AgentSearch and texts). Targeted run: 46 tests in 6 suites passed (FindAgentsTests 10/10). Full suite `swift test`: 578 tests in 80 suites passed, 0 failed.
    - next: /review. Not committed. Task stays in doing.
  timestamp: 2026-10-16T18:24:00.250787+00:00
- actor: claude-code
  id: 01m52zbrka36rmtc3ktcxs46mt
  text: |-
    ### test — green
    - evidence: `swift test` ran one time. 578 tests in 80 suites passed. 0 failures. 0 skipped. 0 compiler warnings.
    - note: The only warning line is the known SwiftPM line "missing creator for mutated node" for the mlx-swift_Cmlx bundle of a dependency. It is accepted.
    - note: Two test names contain the word "skipped". They are tests of skill loading and they passed. They are not skipped tests.
    - next: review. No code changed in this step. No commit made.
  timestamp: 2026-10-16T18:25:04.618397+00:00
position_column: doing
position_ordinal: '80'
title: 'A find agents operation: select agents by a semantic search of the descriptions (D61)'
---
## Why

Decision D61 of the SwissArmyHammer app: a `find agents` operation selects agents with a semantic search of the descriptions (embedding), and then a small model picks, as the skills selection does.

## Conflict with a current decision

`docs/skills-and-agents.md:84` says: "`search skill` — Not copied. `list agents` gives the full catalog." D61 replaces this decision. The app session agreed. Update that row in the same change as the operation, so that the doc does not tell about an operation that does not exist yet.

## Plan

1. Examine how FoundationModelsSkills does the selection (`skillsSelectionModel`, the embedding search, the pick by a small model). Use the same parts. Do not copy them.
2. Add `find agents` to the `agents` tool. It searches `modelVisible` agents only, thus an agent with no description is never found.
3. Keep the embedding index current with each catalog from `onReload`.
4. Update `docs/skills-and-agents.md` (the `search skill` row and the D61 reason) and the DocC page of the `agents` tool.

## Acceptance

- Tests with a fixture catalog: a query finds the correct agent; a hidden agent is not found.
- The docs tell the operation.