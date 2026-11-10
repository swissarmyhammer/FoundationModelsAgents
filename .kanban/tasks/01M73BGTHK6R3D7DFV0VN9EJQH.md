---
assignees:
- claude-code
depends_on:
- 01M73B5MRN6NYWGR5H92YBA9PF
position_column: todo
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