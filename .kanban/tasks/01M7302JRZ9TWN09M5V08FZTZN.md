---
assignees:
- claude-code
depends_on:
- 01M73022AZKH760297EN693YD3
position_column: todo
position_ordinal: '8180'
title: 'AG-9: the agents tool gets add agent, edit agent and remove agent, with the layer option'
---
## What
Add the three write operations of AG-9 to `AgentsTool`. They use `AgentWriter` (task `^n693yd3`).

- New file `Sources/FoundationModelsAgents/Tool/AgentsToolWriteOperations.swift` with three `@Generable @Operation` structs, in the same form as `StartAgent` in `Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift`. Each has `mount: ToolMount(mode: .runToCompletion)`:
  - `AddAgent` (`add agent`): `name` (the id), `content` (the full text of `AGENT.md`), `layer` (optional).
  - `EditAgent` (`edit agent`): `name`, `content` (the full new text), `document` (optional, a relative path in the agent folder, default `AGENT.md`), `layer` (optional).
  - `RemoveAgent` (`remove agent`): `name`, `layer` (optional).
- Each `name` field has the same `@OperationParam(aliases: [...])` list as `StartAgent.name` (`agent`, `agentName`, `agentID`, …). The existing `agentNameConflict` check of `AgentsTool` applies to each op whose noun is `agent`, so a call with a `name` and an `agent` that differ gets the same corrective as `start agent`.
- `layer` is a string, `user` or `project`, and an absent `layer` is `user` (D175). Its `@Guide` text: "Optional. Where to write: user (the user folder, for all projects) or project (the .agents folder of this project). Leave it out for user." Send this text to the skills session (SK-6) so that both tools use the same text. An other value gives a corrective that names the two values.
- Verb aliases. `OperationResolver.defaultVerbAliases` (module `Operations` of FoundationModelsExtras) maps `remove`, `rm` and `del` to `delete`. Thus without a change, `remove agent` resolves to `delete agent`, which is not an operation. Add these entries to `AgentsTool.verbAliases`, which go over the defaults: `remove` → `remove`, `delete` → `remove`, `rm` → `remove`, `del` → `remove`, `update` → `edit`, `change` → `edit`. `create` → `add` and `new` → `add` come from the defaults.
- Each operation: call `AgentWriter`, then `try await context.runner.registry.reload()`. The answer names each file or folder that changed and the layer.
- After `add agent`, and after `edit agent` of `AGENT.md`, the answer also gives the diagnostics of the new catalog for that id. When the agent is not in the new catalog (a skip), the answer says so and gives the reason, so the model can correct the file.
- Change events. A reload gives a change event on the `agents` endpoint only when the catalog content of an id changes (`AgentCatalogChanges.change(from:to:)`). Thus `add agent`, `remove agent` and an `edit agent` that changes the winning `AGENT.md` give one event. An edit of a resource document, an edit with the same text, and an edit of a copy that a higher layer hides give no event. For these, the answer says that the catalog did not change, and for a hidden copy it names the layer that wins.
- A writer error gives `.failure` with the corrective message of `AgentWriterError`. No gate (D78, D87).
- Register the three operations in `AgentsTool.operations(of:)` for `.full`, after `cancel agent`. `.messagingOnly` does not get them. A child run whose `tools` lists `Agent` also has `.full`, so it can write agents too. AG-9 and D87 put no gate on the writes, so this is the intended result. A test pins it.
- Update `AgentsToolDescription` (`Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift`): one sentence for the write operations and the `layer` option.
- `start agent` of a new agent in the same session works, because `startableAgents` reads the live catalog.

## Acceptance Criteria
- [ ] `{"op": "add agent", "name": "reviewer", "content": "..."}` writes `<user layer root>/reviewer/AGENT.md`. The catalog then holds `reviewer` from the user layer, and `start agent` with `reviewer` starts it.
- [ ] The same call with `"layer": "project"` writes `<project layer root>/reviewer/AGENT.md`.
- [ ] `edit agent` with `name: "default"` changes the root `AGENT.md` of the user layer, and `AgentRunner` gives the new default instructions.
- [ ] `remove agent` deletes the agent, and the agent is not in the catalog after the call.
- [ ] `{"op": "delete agent", ...}`, `rm agent`, `create agent` and `update agent` resolve to the correct operation.
- [ ] `add agent`, `remove agent` and an `edit agent` of the winning `AGENT.md` each give one change event on the `agents` endpoint. An edit of a resource document gives no event, and its answer says that the catalog did not change.
- [ ] A tool with `.messagingOnly` has no write operation. A child-run tool with `.full` has the write operations.
- [ ] A bad `layer`, a bad id, a reserved id and a missing agent give a corrective failure, and no file changes.

## Tests
- [ ] New `Tests/FoundationModelsAgentsTests/AgentsToolWriteTests.swift`: call each operation through the tool with a temporary `user < project` stack and a registry with `watch: false`. Check the files, the catalog after the call, the answer text, the diagnostics of an add with a frontmatter warning, the skip report of an add with no frontmatter, the `agent` alias of `name`, and the `name`/`agent` conflict corrective.
- [ ] In `AgentsToolWriteTests.swift`: subscribe to the changes of `AgentsGraph` (as in `Tests/FoundationModelsAgentsTests/AgentsGraphChangesTests.swift`). Check one event for `add agent`, `remove agent` and an edit of `AGENT.md`. Check no event for an edit of a resource document and for an edit of a hidden copy.
- [ ] In `AgentsToolWriteTests.swift`: resolve `delete agent`, `rm agent`, `create agent` and `update agent`, and check the operation of each.
- [ ] Update `Tests/FoundationModelsAgentsTests/AgentsToolSchemaTests.swift`: `opStrings` gets the three ops, `messageOpStrings` does not, `eachOperationDeclaresItsParameters` gets their parameters, and the pinned schema gets `content`, `document` and `layer`.
- [ ] Update `Tests/FoundationModelsAgentsTests/AgentsToolMountTests.swift`: `modes` gets `.runToCompletion` for the three ops and their aliases.
- [ ] Update `Tests/FoundationModelsAgentsTests/AgentsToolDescriptionTests.swift` for the new sentence.
- [ ] Add a test that the tool of a child run with `Agent` in its `tools` has the write operations.
- [ ] `swift build --build-tests` gives no error and no warning. `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1 #AG-9
