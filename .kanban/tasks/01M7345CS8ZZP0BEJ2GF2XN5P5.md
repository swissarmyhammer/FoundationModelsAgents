---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
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
- [ ] `sessionAgentInstructions(for:)` of a named agent that is not `default` gives its rendered body and the bodies of its `skills:` preload, in order.
- [ ] `sessionAgentInstructions(for:)` accepts a definition from `rootAgent(in:)` of a folder that is not a layer of the registry.
- [ ] `defaultAgentInstructions()` gives the same result as before for the default agent.
- [ ] `rootAgent(in:)` gives the definition for a folder with an `AGENT.md`, a nil definition and no diagnostic for a folder with no `AGENT.md`, and diagnostics for a file with no frontmatter.
- [ ] `rootAgent(in:id:)` gives the definition the id of the call, and the id `default` when the call gives no id. An invalid id gives a nil definition and an `invalidID` diagnostic.
- [ ] `rootAgent(in:)` does not load `<folder>/<id>/AGENT.md` or `<folder>/agents/<id>/AGENT.md`.
- [ ] No type with the name `DefaultAgentInstructions` remains.

## Tests
- [ ] New `Tests/FoundationModelsAgentsTests/SessionAgentInstructionsTests.swift`: a named non-default agent with a body and a `skills:` key renders its body and its skills; a definition from `rootAgent(in:)` renders, also with a partial; `defaultAgentInstructions()` is unchanged.
- [ ] New `Tests/FoundationModelsAgentsTests/RootAgentTests.swift`: a folder with an `AGENT.md`; a folder with none; a file with no frontmatter; a call with `id: "reviewer"` and a call with no id; a call with an invalid id; a folder that also has `reviewer/AGENT.md` and `agents/helper/AGENT.md` (neither loads).
- [ ] Update each existing test that names `DefaultAgentInstructions`.
- [ ] `swift build --build-tests` gives no error and no warning. `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1 #ACPA-1