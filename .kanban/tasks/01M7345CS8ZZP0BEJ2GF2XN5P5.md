---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7353htzy8hfd3jqn40gr4zy
  text: |-
    Research:
    - `AgentBodyRenderer.scopedLayers(of:)` does not use the catalog or a layer index. For the agent folder form (also `.rootDocument`) it uses `[definition.layer]` only. Thus a definition from `rootAgent(in:)` (kind `.rootDocument`, layer at the folder) renders with the partials of its folder, also when the registry does not have that layer. The renderer needs no code change; its doc comment gets a sentence for this.
    - `AgentFolderFormScan` (private in AgentLayerScan.swift) makes the root copy with the fixed id `default`. Plan: a static `rootCopy(of:in:at:)` that takes the id, used by the scan and by `rootAgent(in:id:)`.
    - `AgentCatalogBuilder.readWinner` does the coordinated read (through `FileCoordination`), the not-local skip, the enabled rule and the rule table. Plan: one internal builder entry that reads one root copy with `readWinner`, so the parser and the read are the same as the catalog build.
    - The only callers of `DefaultAgentInstructions` are AgentRunner+DefaultAgent.swift and DefaultAgentTests.swift (the tests use `defaultAgentInstructions()` only). LoadingTheCatalog.md names `defaultAgentInstructions()`; RunningAnAgent.md does not name the type yet.
  timestamp: 2026-11-10T16:36:50.655008+00:00
- actor: claude-code
  id: 01m735fjcwszxez2dze8443tnq
  text: |-
    Implementation landed (TDD: each new suite failed to compile first, for the missing API, then passed).
    - `AgentFolderFormScan` is now internal, with `rootCopy(of:in:at:)` that takes the id. The catalog scan uses the same helper for its root copy with the id `default`.
    - `AgentCatalogBuilder.loadRootCopy(_:of:)` reads one root copy with `readWinner`. Thus `rootAgent(in:id:)` uses the same coordinated read (`FileCoordination`), the same not-local skip and the same rule table as the build.
    - `AgentBodyRenderer` needed no code change: for the agent folder form it uses `[definition.layer]` only. Its doc comment now states this.
    - An invalid id is checked before the scan, thus it gives one `invalidID` diagnostic also when the folder has no `AGENT.md`. The diagnostic uses `AgentDefinitionRules.invalidIDFinding`, whose message says "the folder name"; the value is the id of the call.
    - Discovery: `AgentFolderFixture.agentText` puts a blank line before the body, thus a rendered body starts with a newline. The new tests that compare a full body use a local helper with no blank line.
    - No existing test named the type `DefaultAgentInstructions`. DefaultAgentTests calls `defaultAgentInstructions()` only, and it passes with no change.
    - Docs: RunningAnAgent.md gets the section "The instructions of a main session" (it did not name the old type). LoadingTheCatalog.md names `sessionAgentInstructions(for:)` and `rootAgent(in:id:)`. The Topics of FoundationModelsAgents.md list `RootAgentLoad` and `SessionAgentInstructions`.
  timestamp: 2026-11-10T16:43:24.444338+00:00
- actor: claude-code
  id: 01m735fnmzbqa41nxae7884ybn
  text: |-
    ### implement — changed
    - evidence: 12 files — Sources/FoundationModelsAgents/Run/AgentRunner+DefaultAgent.swift, Sources/FoundationModelsAgents/Run/AgentBodyRenderer.swift, Sources/FoundationModelsAgents/Registry/AgentRegistry+RootAgent.swift (new), Sources/FoundationModelsAgents/Registry/AgentLayerScan.swift, Sources/FoundationModelsAgents/Registry/AgentCatalogBuilder.swift, Sources/FoundationModelsAgents/FoundationModelsAgents.docc/RunningAnAgent.md, LoadingTheCatalog.md, FoundationModelsAgents.md, Tests/FoundationModelsAgentsTests/RootAgentTests.swift (new, 11 tests), Tests/FoundationModelsAgentsTests/SessionAgentInstructionsTests.swift (new, 5 tests); `swift build --build-tests`: 0 errors, 0 warnings in our code (only the known mlx "missing creator" note); `swift test`: 882 tests in 118 suites passed.
    - next: /review
  timestamp: 2026-11-10T16:43:27.775071+00:00
- actor: claude-code
  id: 01m735p75ad6vweayw38mrkbnx
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (ab975d5): 1 finding (1 confirmed, 3 refuted, 7 files attempted, 0 failed). Tests/FoundationModelsAgentsTests/SessionAgentInstructionsTests.swift:120 reuse/reuse.
    - next: move makeRunner(registry:skills:) to the shared Support file so that SessionAgentInstructionsTests and DefaultAgentTests call one helper. Then commit and review again.
  timestamp: 2026-11-10T16:47:02.314261+00:00
- actor: claude-code
  id: 01m735pk775jk21zwv5kwbqpt3
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 10 files (AgentRegistry+RootAgent.swift, RootAgentTests.swift, SessionAgentInstructionsTests.swift new; AgentRunner+DefaultAgent.swift, AgentBodyRenderer.swift, AgentLayerScan.swift, AgentCatalogBuilder.swift, 3 DocC articles)
    - test: green — swift build --build-tests 0 warnings in our code; swift test 882 passed in 118 suites
    - commit: ab975d5
    - review: findings — Tests/FoundationModelsAgentsTests/SessionAgentInstructionsTests.swift:120
  timestamp: 2026-11-10T16:47:14.663806+00:00
- actor: claude-code
  id: 01m735wcj613jc9patpkav2chy
  text: |-
    Finding fixed: new `Tests/FoundationModelsAgentsTests/Support/SessionInstructionsFixture.swift` holds one `makeRunner(registry:skills:)`, one `makeSkills(in:)` (it writes `do-task`, `checklist` and the hidden `deploy`), one `skillText(_:body:extraKeys:)`, and the shared skill constants. DefaultAgentTests and SessionAgentInstructionsTests call them through a private typealias `Fixture` (the prevailing typealias pattern of AgentRunMetricsTests). No copy of a helper or of a skill constant remains in either suite. The hidden `deploy` skill has no effect on SessionAgentInstructionsTests, because its `skills:` key names only `do-task` and `checklist`. Unused imports (`FoundationModelsSkills`, and `FoundationModelsExtras` in SessionAgentInstructionsTests) removed.

    ### implement — changed
    - evidence: 3 files — Tests/FoundationModelsAgentsTests/Support/SessionInstructionsFixture.swift (new), Tests/FoundationModelsAgentsTests/DefaultAgentTests.swift, Tests/FoundationModelsAgentsTests/SessionAgentInstructionsTests.swift; `swift build --build-tests`: 0 errors, 0 warnings in our code (only the known mlx "missing creator" note); `swift test`: 882 tests in 118 suites passed.
    - next: /review
  timestamp: 2026-11-10T16:50:24.454237+00:00
position_column: doing
position_ordinal: '80'
title: 'ACPA-1: AgentRunner renders the instructions of any agent for a main session, and AgentRegistry reads the root AGENT.md of a folder'
---
## What
FoundationModelsACPAgent (task `^p21q32s`, ACPA-1) waits on two public APIs. testudoapp-75 gave this task priority over the AG-9 tasks that did not start yet.

1. Rename `DefaultAgentInstructions` to `SessionAgentInstructions` in `Sources/FoundationModelsAgents/Run/AgentRunner+DefaultAgent.swift` (no alias: see ARCHITECTURE.md). Change each caller in this package.
2. Add `public nonisolated func sessionAgentInstructions(for definition: AgentDefinition) async throws(AgentRunFailure) -> SessionAgentInstructions` in an extension of `AgentRunner` in the same file. It does the same work as `defaultAgentInstructions()` today: `body` from `renderer.render(definition, prompt: "")`, `skillBodies` from `environment.skillsPreload.bodies(of:)`, `diagnostics` from `environment.skillsPreload.diagnostics(of:)`. The render uses the partials of `definition.kind` and the skills visibility of the environment. It accepts a definition that is not in the catalog of `registry` (for example the result of item 3). Read `AgentBodyRenderer` (`Sources/FoundationModelsAgents/Run/AgentBodyRenderer.swift`): if it finds the partials through the catalog or the layer index of the registry, change it so that it uses the provenance of the definition. A definition that names a layer that the registry does not have must still render.
3. `defaultAgentInstructions()` calls `sessionAgentInstructions(for:)` with `registry.catalog().defaultAgent`, and gives `nil` when there is no default agent.
4. Add `public static func rootAgent(in folder: URL, id: String = AgentCatalog.defaultAgentID) -> RootAgentLoad` to `AgentRegistry` in a new file `Sources/FoundationModelsAgents/Registry/AgentRegistry+RootAgent.swift`. `RootAgentLoad` is a public struct with `definition: AgentDefinition?` and `diagnostics: [AgentDiagnostic]`. It reads only `<folder>/AGENT.md` (D71: a folder with an `AGENT.md` at its root is an agent), with the same coordinated read and the same parser as the catalog build (`AgentCatalogBuilder`, `AgentFolderFormScan` in `AgentLayerScan.swift`), as a layer with the source `.project` at `folder`. The definition gets the id that the caller gives. The default is `AgentCatalog.defaultAgentID`, as for the root `AGENT.md` of a local layer. ACPAgent gives `<name>` for a folder `Agents/<name>/`, so the id is the same as the catalog id of that agent (D70). An id that `AgentDefinitionRules.isValidID` refuses gives a nil definition and an `invalidID` diagnostic. It does not read `<folder>/<id>/AGENT.md` or `<folder>/agents/`. No file gives a nil definition and no diagnostic. A file that is not valid gives a nil definition and its diagnostics. A placeholder file (not downloaded) gives a nil definition and the same diagnostic as the catalog build.
5. Update the doc comments, and the DocC article `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/RunningAnAgent.md` where it names `DefaultAgentInstructions`.

## Acceptance Criteria
- [x] `sessionAgentInstructions(for:)` of a named agent that is not `default` gives its rendered body and the bodies of its `skills:` preload, in order.
- [x] `sessionAgentInstructions(for:)` accepts a definition from `rootAgent(in:)` of a folder that is not a layer of the registry.
- [x] `defaultAgentInstructions()` gives the same result as before for the default agent.
- [x] `rootAgent(in:)` gives the definition for a folder with an `AGENT.md`, a nil definition and no diagnostic for a folder with no `AGENT.md`, and diagnostics for a file with no frontmatter.
- [x] `rootAgent(in:id:)` gives the definition the id of the call, and the id `default` when the call gives no id. An invalid id gives a nil definition and an `invalidID` diagnostic.
- [x] `rootAgent(in:)` does not load `<folder>/<id>/AGENT.md` or `<folder>/agents/<id>/AGENT.md`.
- [x] No type with the name `DefaultAgentInstructions` remains.

## Tests
- [x] New `Tests/FoundationModelsAgentsTests/SessionAgentInstructionsTests.swift`: a named non-default agent with a body and a `skills:` key renders its body and its skills; a definition from `rootAgent(in:)` renders, also with a partial; `defaultAgentInstructions()` is unchanged.
- [x] New `Tests/FoundationModelsAgentsTests/RootAgentTests.swift`: a folder with an `AGENT.md`; a folder with none; a file with no frontmatter; a call with `id: "reviewer"` and a call with no id; a call with an invalid id; a folder that also has `reviewer/AGENT.md` and `agents/helper/AGENT.md` (neither loads).
- [x] Update each existing test that names `DefaultAgentInstructions`.
- [x] `swift build --build-tests` gives no error and no warning. `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1 #ACPA-1

## Review Findings (2026-11-10 10:45)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 5 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 3 file(s) not reviewed — no validator matched:
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/FoundationModelsAgents.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/LoadingTheCatalog.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/RunningAnAgent.md` — no validator matches this file

- [x] `Tests/FoundationModelsAgentsTests/SessionAgentInstructionsTests.swift:120` `reuse/reuse` — The new makeRunner(registry:skills:) is the same helper as DefaultAgentTests.makeRunner. Both wrap AgentRunHarness.make and return the harness and its runner. The copy adds one more place that must change if the harness setup changes. Move makeRunner into the shared Support file with makeSkills, as in the finding on makeSkills. Both suites then call one helper.
