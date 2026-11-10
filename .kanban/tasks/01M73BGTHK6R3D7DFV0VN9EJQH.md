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
- actor: claude-code
  id: 01m73cvk6s45xjp71d1w1292qk
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (8de0f79). 1 finding (1 confirmed, 0 refuted). Sources/FoundationModelsAgents/Run/AgentEnvironment.swift:425 (duplication/duplication).
    - next: Make one `SkillsTool.make` call in `makeSkillsTool`, so that `sandboxProbe` and the other shared arguments occur in one location only. Then review again.
  timestamp: 2026-11-10T18:52:18.521639+00:00
- actor: claude-code
  id: 01m73cw1qpphpq2fg6jj239gt7
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — AgentEnvironment.swift, RunningAnAgent.md, DelegatingWithTheAgentsTool.md, AgentEnvironmentTests.swift, Support/AgentRunHarness.swift
    - test: green — root swift build --build-tests clean; swift test 916 passed in 119 suites; IntegrationTests build clean
    - commit: 8de0f79
    - review: findings — Sources/FoundationModelsAgents/Run/AgentEnvironment.swift:425
  timestamp: 2026-11-10T18:52:33.398163+00:00
- actor: claude-code
  id: 01m73d2m7faas0k3t6dkbnjjyy
  text: 'Finding fix (duplication): FoundationModelsSkills b4e39c5 has two public `SkillsTool.make` overloads. One takes `model: any LanguageModel`, which is not optional. The other takes no model. Both go to the private `assemble`, thus no public call takes an optional model, and one direct call is not possible. The fix is a private `SkillsToolFactory` typealias with the shape of the overload that takes no model, and a private `skillsToolFactory(selectionModel:)`. With `nil` it gives the unapplied reference to that overload. With a model it gives a closure that binds the model. `makeSkillsTool` now gives registry, embedder (nil), followReloads (true), catalogCharacterLimit, visibilityPredicate and sandboxProbe in one call only. The values are the same as the defaults before, thus behavior is the same. A doc comment tells why two overloads are necessary.'
  timestamp: 2026-11-10T18:56:08.943599+00:00
- actor: claude-code
  id: 01m73d2p6zmaccwyj5g8p5rcqr
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsAgents/Run/AgentEnvironment.swift. `swift build --build-tests`: 0 errors, 0 warnings in our code (only the known mlx "missing creator" note). `swift test`: 916 tests in 119 suites passed, with the 4 sandbox-probe tests. No new test: the change is a refactor with the same behavior. Finding flipped to `- [x]`.
    - next: /review
  timestamp: 2026-11-10T18:56:10.975651+00:00
- actor: claude-code
  id: 01m73d7avmepm7br02adbvxenr
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (b28bb8c). 0 findings, 0 confirmed, 0 refuted; 7 validator runs attempted, 0 failed. 1 file reviewed. All prior Review Findings items are checked.
    - next: none. The task is in done.
  timestamp: 2026-11-10T18:58:43.189+00:00
- actor: claude-code
  id: 01m73d7p0baz5r2cm5k63cfq7v
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — AgentEnvironment.swift (one SkillsTool.make call path through skillsToolFactory(selectionModel:))
    - test: green — root swift build --build-tests clean; swift test 916 passed in 119 suites; IntegrationTests build clean
    - commit: b28bb8c
    - review: clean — 0 findings; 1 of 1 prior item checked; task moved to done
  timestamp: 2026-11-10T18:58:54.603909+00:00
depends_on:
- 01M73B5MRN6NYWGR5H92YBA9PF
position_column: done
position_ordinal: ff9080
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

## Review Findings (2026-11-10 12:51)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 4 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/RunningAnAgent.md` — no validator matches this file

- [x] `Sources/FoundationModelsAgents/Run/AgentEnvironment.swift:425` `duplication/duplication` — The two `SkillsTool.make` calls in `makeSkillsTool` are near-verbatim copies that differ only by the `model:` argument. This change added `sandboxProbe: sandboxProbe` to both copies, so each future argument change must be made in two places and can drift out of sync. Parameterize the difference: pass the optional selection model into one `SkillsTool.make` call if its signature allows an optional model, or compute the model argument once and make a single call. Then `sandboxProbe` and the other shared arguments appear in one place only.
