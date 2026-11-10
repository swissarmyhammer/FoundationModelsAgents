---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m73grg5teaztgbz0wyp9pec0
  text: |-
    Research and implementation notes:
    - AgentSessionMaker holds the AgentEnvironment. Thus the maker reads `environment.instructionsPreamble` directly, and no caller of `AgentSessionMaker(...)` changes. The new run (`makeSession`) and the restore (`AgentRun.restore` -> `resolveSetup`) both use the private `instructions(parts:in:)`. No other source path makes run instructions (checked: `instructionsSeparator`, `makeSession(`, `restoreSession(`).
    - `AgentEnvironment.make` takes `instructionsPreamble: String? = nil` just before `sandboxProbe`, thus `sandboxProbe` stays last. The internal init takes it as its last parameter with a default. All callers use labels with defaults, thus no caller changes. The three DocC symbol links of `make(...)` now name `instructionsPreamble:`.
    - Tests in `Tests/FoundationModelsAgentsTests/InstructionsPreambleTests.swift`. The restore test uses `RestoredRunFixture.make(deferStart: true, instructionsPreamble:)` and reads the instructions entry of the transcript of `run.heldSession`: the Router replaces the leading instructions entry on a restore with supplied instructions, while `index.md` keeps the recorded string.
    - Test support: `AgentRunHarness.environment(...)`, `makeRunner(...)`, `RestoredRunFixture.make(...)` and `RestoredRunFixture.makeRunner(...)` take `instructionsPreamble`. The `agentText(name:body:skills:)` helper moved from `SessionAgentInstructionsTests` to `SessionInstructionsFixture`, so both suites use one helper.
    - TDD: RED was first a compile error, then two behavior failures (new run and restore). The whitespace case was checked with a mutation (guard removed: 2 issues), then the guard was put back.
  timestamp: 2026-11-10T20:00:31.418548+00:00
- actor: claude-code
  id: 01m73grky1xhr3b162ne9c2wxs
  text: |-
    ### implement — changed
    - evidence: 10 files — Sources/FoundationModelsAgents/Run/AgentEnvironment.swift, Sources/FoundationModelsAgents/Run/AgentSessionMaker.swift, Sources/FoundationModelsAgents/Run/AgentRunner+DefaultAgent.swift, Sources/FoundationModelsAgents/FoundationModelsAgents.docc/RunningAnAgent.md, Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md, Tests/FoundationModelsAgentsTests/InstructionsPreambleTests.swift (new), Tests/FoundationModelsAgentsTests/SessionAgentInstructionsTests.swift, Tests/FoundationModelsAgentsTests/Support/AgentRunHarness.swift, Tests/FoundationModelsAgentsTests/Support/RestoredRunFixture.swift, Tests/FoundationModelsAgentsTests/Support/SessionInstructionsFixture.swift. `swift build --build-tests`: 0 errors, 0 warnings in our code (only the known mlx "missing creator" note). `swift test`: 939 tests in 122 suites passed, 0 failed. `swift build --build-tests` in IntegrationTests/: Build complete, 0 errors, 0 warnings.
    - next: /review
  timestamp: 2026-11-10T20:00:35.265679+00:00
- actor: claude-code
  id: 01m73h56e6r0jwjda9c2x4e808
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (3a2bfca). counts: findings 1, confirmed 1, refuted 2. Tests/FoundationModelsAgentsTests/Support/SessionInstructionsFixture.swift:63 (reuse/reuse).
    - next: Add a `skills: [String] = []` parameter to `AgentFolderFixture.agentText`, delete `SessionInstructionsFixture.agentText`, and move its callers to `AgentFolderFixture.agentText`. Then commit and review again.
  timestamp: 2026-11-10T20:07:27.430187+00:00
- actor: claude-code
  id: 01m73h5jzf3nkq01y87e9fbven
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — AgentEnvironment.swift, AgentSessionMaker.swift, AgentRunner+DefaultAgent.swift, 2 DocC articles, InstructionsPreambleTests.swift (new), 4 test support files
    - test: green — root swift build --build-tests clean; swift test 939 passed in 122 suites; IntegrationTests build clean
    - commit: 3a2bfca
    - review: findings — Tests/FoundationModelsAgentsTests/Support/SessionInstructionsFixture.swift:63
  timestamp: 2026-11-10T20:07:40.271464+00:00
- actor: claude-code
  id: 01m73he649xzhv2p9vbhmznmcq
  text: |-
    Finding fix (reuse/reuse, SessionInstructionsFixture.agentText):
    - `AgentFolderFixture.agentText(name:description:body:skills:)` now takes `skills: [String] = []`. It writes the `skills: [...]` line only when the list is not empty. `SessionInstructionsFixture.agentText` is deleted.
    - Callers moved to `AgentFolderFixture.agentText`: `SessionAgentInstructionsTests.makeLayer` and its root-agent test, `InstructionsPreambleTests.makeLibrary`. A `skills: []` argument is now no argument (the agent has no skills key; same result).
    - Search of the test target for other functions that write the same frontmatter text (only `name`, `description`, optional `skills`, body): `SkillsPreloadTests.agentFile(_:skills:)` (deleted, the caller uses the shared helper), `AgentBodyRendererTests.agentFile(body:)` and `DefaultAgentTests.defaultAgentText(body:skills:)` (now one-line forwards to the shared helper; the unused `extraKeys` parameter of `defaultAgentText` is removed).
    - Not changed: the functions that write other keys (`model: flash`, `enabled:`, `tools:`, `compactionPrompt:` by `extraKeys`) in `CatalogNoticeTests`, `ReloadDuringRunTests`, `EnabledAgentTests`, `AgentLaunchingTests`, `AgentRunTests`. Their text is not the same frontmatter.
    - Discovery: the frontmatter reader does not trim the body. The old shared helper wrote a blank line after the closing `---`, so the body started with a newline. With that blank line, 9 exact-body expectations failed. The shared helper now writes the body directly after `---`. All existing callers still pass.
  timestamp: 2026-11-10T20:12:22.025605+00:00
- actor: claude-code
  id: 01m73he8n9av48g2ahbde7w880
  text: |-
    ### implement — changed
    - evidence: 7 files — Tests/FoundationModelsAgentsTests/Support/AgentFolderFixture.swift, Tests/FoundationModelsAgentsTests/Support/SessionInstructionsFixture.swift, Tests/FoundationModelsAgentsTests/SessionAgentInstructionsTests.swift, Tests/FoundationModelsAgentsTests/InstructionsPreambleTests.swift, Tests/FoundationModelsAgentsTests/SkillsPreloadTests.swift, Tests/FoundationModelsAgentsTests/AgentBodyRendererTests.swift, Tests/FoundationModelsAgentsTests/DefaultAgentTests.swift. `swift build --build-tests`: Build complete, 0 errors, 0 warnings in our code (only the known mlx "missing creator" note). `swift test`: 939 tests in 122 suites passed.
    - next: /review
  timestamp: 2026-11-10T20:12:24.617942+00:00
- actor: claude-code
  id: 01m73hk9j6p2gd6368vgpms4n7
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (bc848c5): 0 findings, 0 confirmed, 0 refuted; 7 files attempted, 0 failed. All prior Review Findings items are checked.
    - next: none. The task is in done.
  timestamp: 2026-11-10T20:15:09.382691+00:00
- actor: claude-code
  id: 01m73hkkv99ywbkf7vweg35s40
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 7 test files (one AgentFolderFixture.agentText helper)
    - test: green — root swift build --build-tests clean; swift test 939 passed in 122 suites; IntegrationTests build clean
    - commit: bc848c5
    - review: clean — 0 findings; 1 of 1 prior item checked; task moved to done
  timestamp: 2026-11-10T20:15:19.913914+00:00
depends_on:
- 01M73DBP7JAF6N8K5V71YB868R
position_column: done
position_ordinal: ff9380
title: 'ACPA-20: AgentEnvironment takes an instructions preamble, and each run starts its instructions with it'
---
## What
FoundationModelsACPAgent (ACPA-20, D153) needs each agent, also each sub-agent run, to start its instructions with a built-in style text (short answers in Simplified Technical English), before the `AGENTS.md` text. Today a run makes its instructions in the private `AgentSessionMaker.instructions(parts:in:)` (`Sources/FoundationModelsAgents/Run/AgentSessionMaker.swift`): the `AGENTS.md` documents, then the body, then the skill bodies. The host has no way to add text before the `AGENTS.md` text.

- `Sources/FoundationModelsAgents/Run/AgentEnvironment.swift`: add `instructionsPreamble: String? = nil` to the public `AgentEnvironment.make`, and store it as `public let instructionsPreamble: String?`. Give it to each place that makes an `AgentSessionMaker` (or to the maker), so that the maker can read it.
- `AgentSessionMaker.instructions(parts:in:)`: join `[preamble] + documents + parts` with `instructionsSeparator`. Leave out a `nil` preamble, and a preamble that holds only whitespace. A new run and a restored run (the restore path, for example `resolveSetup` in `AgentRunRestore`) both use this function, so both get the preamble. Check that no other path makes run instructions without it.
- `AgentRunner.sessionAgentInstructions(for:)` and `defaultAgentInstructions()` do not add the preamble. ACPAgent adds it to the main session itself, so the text occurs one time. State this in their doc comments.
- Update the doc comments of `AgentEnvironment.make` and the DocC article `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/RunningAnAgent.md` (the order of the instructions of a run).

## Acceptance Criteria
- [ ] A run with a preamble, and with an `AGENTS.md` in its working folder, has instructions that start with the preamble, then the `AGENTS.md` text, then the body, then the skill bodies, joined with `instructionsSeparator`.
- [ ] A run with no preamble, or with a whitespace-only preamble, has the same instructions as before.
- [ ] A restored run gets the preamble too.
- [ ] `sessionAgentInstructions(for:)` and `defaultAgentInstructions()` do not hold the preamble.

## Tests
- [ ] In `Tests/FoundationModelsAgentsTests/` (next to the existing tests of `AgentSessionMaker` or `AgentsMd`): one test for each criterion above. For the restored run, use the restore test support that exists.
- [ ] `swift build --build-tests` gives no error and no warning in our code. `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1 #ACPA-20

## Review Findings (2026-11-10 14:04)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 4 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/RunningAnAgent.md` — no validator matches this file

- [x] `Tests/FoundationModelsAgentsTests/Support/SessionInstructionsFixture.swift:63` `reuse/reuse` — `SessionInstructionsFixture.agentText(name:body:skills:)` is a near-match of the existing `AgentFolderFixture.agentText(name:description:body:)`, which already writes the same agent-file layout. The new function adds a second copy of the same frontmatter template and does not extend the existing one, so the test support now has two sources for the same text that can drift apart. Add a `skills: [String] = []` parameter to `AgentFolderFixture.agentText` and emit the `skills: [...]` line when it is not empty. Then delete the new `SessionInstructionsFixture.agentText` and point `makeLayer`, `makeLibrary`, and the `InstructionsPreambleTests` callers at `AgentFolderFixture.agentText`. Keep the default so existing callers are unchanged.
