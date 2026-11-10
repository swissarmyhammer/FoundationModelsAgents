---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7366y4kg214e4wchevrx0za
  text: |-
    Research done.
    - AgentWriter gives [URL] or throws AgentWriterError (typed). Its `message` is the corrective. The ops give `.corrective(message)`: the tool answer type is CorrectiveOutcome<String>, which has no `.failure` case, thus `.corrective` is the "failure" of the card.
    - The `@OperationParam(aliases:)` macro reads only an array literal, thus each `name` field repeats the literal list of StartAgent.name.
    - `agentNameConflict` keys on the last token `agent` of the op, thus it covers `add agent`, `edit agent`, `remove agent` and their verb aliases with no change of code.
    - The resolver uses `verbAliases[token] ?? token` on the merged table, thus `remove` -> `remove` overrides the default `remove` -> `delete`.
    - The event rule: the ops compare the catalog before the write with the catalog after the reload through `AgentCatalogChanges.change(from:to:)`. That is the same function that feeds the change log, thus the answer says "did not change" exactly when no event is appended for the id.
    - SK-6: FoundationModelsSkills (main, 76393d0) already has `SkillWriteSupport.layerGuide` with the same words ("the .skills folder of this project"). The skills tool reads `layer` with an exact raw-value match and gives "The layer `x` is not valid. Give `user` or `project`, or leave it out for `user`." The agents tool uses the same rule and the same corrective form, so the two tools agree.
  timestamp: 2026-11-10T16:56:10.131435+00:00
- actor: claude-code
  id: 01m736y99wmczf22e3t4fyq610
  text: |-
    Implementation landed (not committed).
    - New: Sources/FoundationModelsAgents/Tool/AgentsToolWriteOperations.swift (AddAgent, EditAgent, RemoveAgent, and the shared AgentsToolWrite steps: read the layer, write, reload, answer). New: AgentsToolWriteText.swift (the sentence "Added/Edited/Removed the agent `x` to/in/from the <layer> layer: `<path>`.", the bad-layer corrective, the catalog report, the not-changed text).
    - AgentsTool: the three ops after `cancel agent` for `.full` only; verb aliases remove/delete/rm/del -> remove, update/change -> edit. AgentsToolDescription: one write sentence before the delegation sentence.
    - Discovery: the `@Operation` macro puts the `@Guide` text into ParamMeta only when it is a plain one-line string literal. A multi-line `"""` literal falls back to the doc comment. Thus each `layer` guide is one plain literal, and a schema test pins the agreed text word for word.
    - Discovery: the first form of the write sentence held "the default", and DefaultAgentTests refuses the word "default" in the tool description. The sentence now says "used when you leave it out".
    - Test support: ChangeEvent (cursor and first event of the `agents` endpoint) moved to Support/ChangeEvent.swift; TemporaryLayer got `snapshot(of:)` and `text(at:)`. AgentsGraphChangesTests and AgentWriterTests use them, thus no copy. The write-test `firstEvent` first checks that the cursor moved, thus a missing event fails at once and does not hang (test rule T1).
    - SK-6: the agreed `layer` text is already in FoundationModelsSkills `SkillWriteSupport.layerGuide` with `.skills`; no message is necessary.
  timestamp: 2026-11-10T17:08:55.228251+00:00
- actor: claude-code
  id: 01m736ybtyne3hv1969xjd77rd
  text: |-
    ### implement — changed
    - evidence: 14 files — new Sources/FoundationModelsAgents/Tool/AgentsToolWriteOperations.swift, Sources/FoundationModelsAgents/Tool/AgentsToolWriteText.swift, Tests/FoundationModelsAgentsTests/AgentsToolWriteTests.swift, Tests/FoundationModelsAgentsTests/Support/ChangeEvent.swift; changed AgentsTool.swift, AgentsToolDescription.swift, AgentWriterTests.swift, AgentsGraphChangesTests.swift, AgentsToolDescriptionTests.swift, AgentsToolMountTests.swift, AgentsToolSchemaTests.swift, Support/TemporaryLayer.swift (+ kanban files). `swift build --build-tests`: 0 errors, 0 warnings. `swift test`: 906 tests in 119 suites passed.
    - next: /review
  timestamp: 2026-11-10T17:08:57.822187+00:00
- actor: claude-code
  id: 01m7376hajxwmww5kb10x0kndv
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (9d6bcc4). 1 finding, 1 confirmed, 3 refuted, 14 attempted, 0 failed. Tests/FoundationModelsAgentsTests/AgentsToolWriteTests.swift:239 (completeness/inverse-operation-coverage).
    - next: Add a test that writes an agent to the project layer, calls remove agent with layer project, and asserts that the project folder is gone and that the answer names the project layer. Then review again.
  timestamp: 2026-11-10T17:13:25.586195+00:00
- actor: claude-code
  id: 01m73771ryfx2kwkvnsznzazdt
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 12 files (AgentsToolWriteOperations.swift, AgentsToolWriteText.swift, AgentsToolWriteTests.swift, Support/ChangeEvent.swift new; AgentsTool.swift, AgentsToolDescription.swift, 6 test files)
    - test: green — swift build --build-tests 0 warnings in our code; swift test 906 passed in 119 suites
    - commit: 9d6bcc4
    - review: findings — Tests/FoundationModelsAgentsTests/AgentsToolWriteTests.swift:239
  timestamp: 2026-11-10T17:13:42.430685+00:00
- actor: claude-code
  id: 01m737e1g52dmgg5ddavrtxf8a
  text: |-
    Finding fixed: the project-layer cases in AgentsToolWriteTests.swift, in the whole file.
    - New tests: remove agent with layer project (the project folder is gone, the user copy stays, the answer names the project layer); remove agent with layer project leaves the user copy in the catalog; edit agent with layer project changes only the project copy; the edit answer names the project layer; the add answer with layer project names the project layer; edit agent and remove agent with layer project of a user-only agent give the notFound corrective (existsIn [.user]) and change no file; edit agent with layer project of the winning AGENT.md gives one change event.
    - New constants: `projectLayer` (from AgentWriteLayer.project) and `agentFiles`. The add test with layer project uses `projectLayer` in place of the literal.
    - The production code already existed, thus the tests passed at once. A check: a temporary change that sets each layer to user made all the new tests fail (12 issues). The source file is restored, with no diff.
  timestamp: 2026-11-10T17:17:31.525874+00:00
- actor: claude-code
  id: 01m737e31zbwx7gwes58z3bgb9
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsAgentsTests/AgentsToolWriteTests.swift (+ kanban files). `swift build --build-tests`: 0 errors, 0 warnings in our code (one SwiftPM warning about the mlx-swift_Cmlx bundle, not our code). `swift test`: 913 tests in 119 suites passed. AgentsToolWriteTests: 29 tests passed.
    - next: /review
  timestamp: 2026-11-10T17:17:33.119396+00:00
- actor: claude-code
  id: 01m737hgvt3r14s2sqg3gngnym
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (ab714fe). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. 1 file reviewed. The 1 prior finding is checked.
    - next: none. The task moved to done.
  timestamp: 2026-11-10T17:19:25.562208+00:00
- actor: claude-code
  id: 01m737htf8rn8hy93v189903y1
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — AgentsToolWriteTests.swift (project-layer cases for add, edit, remove)
    - test: green — swift build --build-tests 0 warnings in our code; swift test 913 passed in 119 suites
    - commit: ab714fe
    - review: clean — 0 findings; 1 of 1 prior item checked; task moved to done
  timestamp: 2026-11-10T17:19:35.400519+00:00
depends_on:
- 01M73022AZKH760297EN693YD3
position_column: done
position_ordinal: ff8d80
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

## Review Findings (2026-11-10 11:10)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 12 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsAgentsTests/AgentsToolWriteTests.swift:239` `completeness/inverse-operation-coverage` — The layer option was added to remove agent, and add agent with layer project is tested (line 95), but no test runs remove agent with layer project. The only remove tests (lines 238-258) use the user layer. The inverse direction of the project-layer write is therefore unproven, and a project-layer remove could delete the wrong folder or miss the project copy. Add one test that writes an agent to the project layer, calls remove agent with layer project, and asserts the project folder is gone and the answer names the project layer.
