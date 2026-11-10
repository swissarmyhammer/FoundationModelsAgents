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
depends_on:
- 01M73DBP7JAF6N8K5V71YB868R
position_column: doing
position_ordinal: '80'
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