---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m73cp2t91vjn2nj08rvehsaw
  text: 'Research: `swift package update FoundationModelsSkills` moved the local pin to b4e39c5 (b1b3121 is an ancestor). Package.resolved is in .gitignore, thus the pin change is local only and is not in the diff. Both `SkillsTool.make` overloads have `sandboxProbe: SandboxProbe = .live`. FoundationModelsSkills re-exports FoundationModelsExtras, thus the test file needs no new import. The internal `makeSkillsTool` now takes `sandboxProbe` with no default; the one other caller, `AgentRunHarness`, gives `.live`. The DocC symbol links to `make(...)` in RunningAnAgent.md and DelegatingWithTheAgentsTool.md and in the init doc comment now include `sandboxProbe:`.'
  timestamp: 2026-11-10T18:49:17.897698+00:00
- actor: claude-code
  id: 01m73cp4mm1mcngt1hqfkqg1zq
  text: |-
    ### implement — changed
    - evidence: AgentEnvironment.swift, AgentEnvironmentTests.swift (4 new tests), Support/AgentRunHarness.swift, docc RunningAnAgent.md, docc DelegatingWithTheAgentsTool.md. RED: the build failed with "extra argument 'sandboxProbe'". `swift build --build-tests`: 0 errors, 0 warnings in our code (only the known mlx "missing creator" note). `swift test`: 916 tests in 119 suites passed.
    - next: /review
  timestamp: 2026-11-10T18:49:19.764462+00:00
depends_on:
- 01M73B5MRN6NYWGR5H92YBA9PF
position_column: doing
position_ordinal: '80'
title: AgentEnvironment.make takes a SandboxProbe and gives it to SkillsTool.make (SK-7d)
---
## What
FoundationModelsSkills b1b3121 (SK-7d, `^zrf64fw`) added `sandboxProbe: SandboxProbe = .live` as the last parameter of both public `SkillsTool.make` overloads. With `.fixed(true)` and an `.open` registry, `make` throws `ToolModeError.openModeInSandbox`. `SandboxProbe` and `ToolModeError` are in FoundationModelsExtras (`Sources/FoundationModelsExtras/Hosting/ToolMode.swift`). ACPAgent (foundationmodelsacpagent-ec) needs a test probe to reach the skills tool through `AgentEnvironment.make`.

- Move the local FoundationModelsSkills pin to b1b3121 or later (`swift package update FoundationModelsSkills`).
- `Sources/FoundationModelsAgents/Run/AgentEnvironment.swift`: add `sandboxProbe: SandboxProbe = .live` as the last parameter of the public `AgentEnvironment.make`, and give it to `makeSkillsTool`, which gives it to each `SkillsTool.make` call. Update the doc comments (the new parameter, and that `make` throws `ToolModeError.openModeInSandbox` when the probe says the process is sandboxed and the registry mode is `.open`).
- No other caller in this package changes behavior: the default is `.live`.

## Acceptance Criteria
- [ ] `AgentEnvironment.make(..., sandboxProbe: .fixed(true))` with a registry in `.open` mode throws `ToolModeError.openModeInSandbox`.
- [ ] The same call with `.fixed(false)`, or with a `.sandboxed` registry, succeeds.
- [ ] A call with no `sandboxProbe` compiles and behaves as before.

## Tests
- [ ] In `Tests/FoundationModelsAgentsTests/AgentEnvironmentTests.swift`: one test for each criterion above.
- [ ] `swift build --build-tests` gives no error and no warning in our code. `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1