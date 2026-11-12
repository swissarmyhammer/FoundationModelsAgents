---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m77v0ej3evmezbcefnbx60vk
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (2a03044): 2 findings (2 confirmed, 2 refuted) — Sources/FoundationModelsAgents/Tools/ToolResolver.swift:109 (duplication/duplication), Sources/FoundationModelsAgents/Tools/ToolResolver.swift:109 (reuse/reuse). No validator matched RunningAnAgent.md.
    - next: Remove the copy of the selection in ToolResolver.selection(of:vocabulary:). Add an overload of AgentDefinition.toolSelection that takes a ToolVocabulary, and make toolSelection(over:hasAgentsTool:) a thin wrapper of it. The task says that toolSelection(over:hasAgentsTool:) does not change, so keep that signature and add the overload.
  timestamp: 2026-11-12T12:16:35.395341+00:00
- actor: claude-code
  id: 01m77v42vpptwvw12zvf0k6z3x
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — ToolCatalog.swift, ToolSelection.swift, ToolResolver.swift, AgentSessionMaker.swift, RunningAnAgent.md, KeptToolTests.swift, ToolResolverTests.swift, AgentToolSelectionTests.swift, AgentDefinitionAttempt.swift, RestoredRunFixture.swift
    - test: green — swift test, 977 tests in 128 suites; IntegrationTests build complete
    - commit: 2a03044
    - review: findings — ToolResolver.swift:109 (duplication), ToolResolver.swift:109 (reuse)
  timestamp: 2026-11-12T12:18:34.486922+00:00
- actor: claude-code
  id: 01m78hf8eb19s9v0ky6zan953d
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (6ae65f6): 2 findings (2 confirmed, 1 refuted) — Sources/FoundationModelsAgents/Tools/ToolResolver.swift:52 (reuse/reuse), Sources/FoundationModelsAgents/Tools/ToolResolver.swift:91 (reuse/reuse).
    - next: Add one private static helper on ToolResolver that builds the AgentToolSelection from the definition, the catalog, and hasAgentsTool. Call it from diagnostics and from resolve. Keep ToolVocabulary(catalog:hasAgentsTool:) as the single place that builds the vocabulary from a catalog.
  timestamp: 2026-11-12T18:49:09.323970+00:00
- actor: claude-code
  id: 01m78hgy8jw27rszb6k40msngh
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — AgentToolSelection.swift, ToolResolver.swift, AgentDefinitionAttempt.swift, ToolResolverTests.swift, KeptToolTests.swift
    - test: green — swift test, 977 tests in 128 suites; IntegrationTests build complete
    - commit: 6ae65f6
    - review: findings — ToolResolver.swift:52, ToolResolver.swift:91 (a first review attempt stopped on a network error; the second attempt gave these)
  timestamp: 2026-11-12T18:50:04.434437+00:00
- actor: claude-code
  id: 01m78hjcbatfh1b7jb1dnmb5bb
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (b3e7650): 0 findings, 0 confirmed, 0 refuted; 7 validator runs, 0 failed, 0 skipped; 1 file reviewed. All prior review findings are checked.
    - next: The task is in done.
  timestamp: 2026-11-12T18:50:51.626928+00:00
- actor: claude-code
  id: 01m78hjs0xxqj5sgznar43g5py
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — ToolResolver.swift
    - test: green — swift test, 977 tests in 128 suites
    - commit: b3e7650
    - review: clean — 0 findings
  timestamp: 2026-11-12T18:51:04.605961+00:00
position_column: done
position_ordinal: ff9b80
title: 'ACPA ^2dyhd2t: ToolCatalog.registerKept gives each run a kept tool made from its definition, with a vocabulary of capability names'
---
## What
FoundationModelsACPAgent ^2dyhd2t: a run must get the same tool filter as the root session. Its `runCode` registry holds only the capabilities that the `tools:` and `disallowedTools:` keys of its agent allow (`web`, `shell`, `git`, `mcp__<server>__<tool>`). Today a factory (`ToolCatalog.Factory = @Sendable () -> any Tool`) does not know the agent, and `tools: [web]` gives an unknown-name warning.

- Sources/FoundationModelsAgents/Tools/ToolCatalog.swift: add `public typealias KeptFactory = @Sendable (_ definition: AgentDefinition) -> any Tool` and `public mutating func registerKept(_ name: String, vocabulary: @escaping @Sendable () -> [String], _ factory: @escaping KeptFactory)`. A kept name must not also be a plain name (precondition).
- Sources/FoundationModelsAgents/Tools/ToolResolver.swift: `resolve` calls each kept factory one time with the definition of the run, for a new run and a restored run (both use `resolveSetup`). `tools:` and `disallowedTools:` never remove a kept tool. The kept tools come after the catalog tools, before the `agents` tool. The resolver gets the definition.
- Sources/FoundationModelsAgents/Tools/ToolSelection.swift: `ToolVocabulary` knows the kept names and their vocabulary names. A plain entry or an MCP pattern (`mcp__<server>`, `mcp__<server>__*`, `mcp__*`) that matches a vocabulary name is not an unknown name, in `resolve` and in `ToolResolver.diagnostics` (`runner.catalog()`). A vocabulary name makes no tool.
- The kept tool names are in the `toolNames` that `AgentEnvironment.runTemplateContext` gets (it gets the names of the resolved tools).
- `AgentDefinition.toolSelection(over:hasAgentsTool:)` does not change.

## Acceptance Criteria
- [x] A kept factory gets the definition of a new run and of a restored run, one time each.
- [x] `tools: [web]`, with `web` in the vocabulary, keeps the kept tool and gives no warning for `web`, in the resolve and in `runner.catalog()`.
- [x] `disallowedTools: [shell]` and `disallowedTools: [<kept name>]` do not remove the kept tool, and give no warning for a vocabulary name.
- [x] An MCP pattern that matches only vocabulary names gives no warning.
- [x] The closure of `runTemplateContext` gets the kept tool name.

## Tests
- [x] Tests/FoundationModelsAgentsTests/KeptToolTests.swift: the rows above.
- [x] `swift test` passes; IntegrationTests builds.

## Workflow
- Use `/tdd`. #step1

## Review Findings (2026-11-12 07:14)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 1 not reviewed.

> 1 file(s) not reviewed — no validator matched:
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/RunningAnAgent.md` — no validator matches this file

- [x] `Sources/FoundationModelsAgents/Tools/ToolResolver.swift:109` `duplication/duplication` — The new private func selection(of:vocabulary:) builds an AgentToolSelection from the same tools, disallowedTools, agent, and provenance arguments as AgentDefinition.toolSelection in AgentToolSelection.swift. Both copies must change together if the selection inputs change, and they can drift apart. Delete the copy in ToolResolver.selection and call the existing AgentDefinition.toolSelection. Extend toolSelection to take the kept names, or accept a prepared ToolVocabulary, so that the resolver can pass ToolVocabulary(catalog:hasAgentsTool:). Do not edit AgentToolSelection.swift:80 beyond that signature change; report any further change there as a separate task.
- [x] `Sources/FoundationModelsAgents/Tools/ToolResolver.swift:109` `reuse/reuse` — The new private `selection(of:vocabulary:)` builds the same AgentToolSelection from the definition's tools and disallowedTools keys as the existing `AgentDefinition.toolSelection(over:hasAgentsTool:)`. Only the vocabulary source differs. Two copies of the mapping can drift apart, and the tests must then check both paths to keep them equal. Make `AgentDefinition.toolSelection` take a `ToolVocabulary` (or add an overload that does), so one function builds the selection. Then `ToolResolver.selection(of:vocabulary:)` calls that function, or is removed, and the `toolSelection(over:hasAgentsTool:)` form becomes a thin wrapper that builds the vocabulary.

## Review Findings (2026-11-12 13:47)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 0 not reviewed.

- [x] `Sources/FoundationModelsAgents/Tools/ToolResolver.swift:52` `reuse/reuse` — The `diagnostics` body builds the selection inline with the same expression that `resolve` builds at line 91. Both copies must stay in step if the vocabulary rule changes. Call the shared private selection helper from `diagnostics` instead of building the vocabulary and selection inline. This is the same fix as the finding at line 91.
- [x] `Sources/FoundationModelsAgents/Tools/ToolResolver.swift:91` `reuse/reuse` — The new `resolve` body rebuilds the agent's tool selection inline: `definition.toolSelection(vocabulary: ToolVocabulary(catalog: catalog, hasAgentsTool: agentsTool != nil))`. The same two-line construction appears in `diagnostics` at line 52. The change also deletes the `selection` helper from `ToolResolver` (semantic diff: deleted function `selection`), so the construction is now duplicated in two places instead of living in one shared helper. Two call sites are enough to justify a shared helper, so the duplication means a future change to the selection rule must be made in two places. Restore one private helper on `ToolResolver`, for example `private static func selection(of definition: AgentDefinition, catalog: ToolCatalog, hasAgentsTool: Bool) -> AgentToolSelection`, and call it from both `diagnostics` and `resolve`. Keep `ToolVocabulary(catalog:hasAgentsTool:)` as the single place that builds the vocabulary from a catalog.
