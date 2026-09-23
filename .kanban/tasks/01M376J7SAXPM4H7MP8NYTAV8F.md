---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m380r9gb51tc7yyn78k5a2qa
  text: |-
    Research:
    - `SkillsRegistry` builds its catalog in its init (no load step). `call(id:arguments:) async throws -> String` renders a body. It throws `UnknownSkillError` for an id that is not in the catalog. It does NOT check model visibility: it renders a `disable-model-invocation: true` skill too. Thus the preload must check visibility itself.
    - `metadata()` gives each catalog entry with `isModelVisible`. The preload and `runner.catalog()` use it to find unknown and not-visible names.
    - A skills layer root is the folder that holds the skill folders (`defaults/skills`), not the agents layer root.
    - Plan: new `Run/AgentSkillsPreload.swift` (selection, diagnostics, bodies). `AgentSessionMaker` appends the bodies after the agent body. `AgentRunner.runWarnings` appends the skill warnings after the tool warnings. A render error of a preloaded skill fails the run with a new case `AgentRunFailure.skillRenderFailed`.
  timestamp: 2026-09-23T20:54:12.235456+00:00
- actor: claude-code
  id: 01m380zmas6d0g0w7qkd1sr66x
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsAgents/Run/AgentSkillsPreload.swift (new), Run/AgentSessionMaker.swift, Run/AgentRunner.swift, Run/AgentRunFailure.swift (new case `skillRenderFailed(skill:description:)`), Tests/FoundationModelsAgentsTests/SkillsPreloadTests.swift (new, 6 tests), Tests/.../Support/AgentRunHarness.swift (`skills:` parameter), Tests/.../AgentBodyRendererTests.swift (switch lists the new case). `swift test --filter SkillsPreloadTests`: 6 passed. swiftlint: 0.
    - notes: Stdlib `compactMap` has no typed throws; `map` has. The preload renders the skills in a task group and keeps the key order through the index.
    - next: test
  timestamp: 2026-09-23T20:58:12.697694+00:00
- actor: claude-code
  id: 01m3815xd9y2m5ysfg4rm66f6m
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings (7 files reviewed, 1 candidate refuted).
    - next: done

    ### finish iteration 1 — clean
    - implement: changed (AgentSkillsPreload, AgentSessionMaker, AgentRunner, AgentRunFailure.skillRenderFailed, SkillsPreloadTests, AgentRunHarness skills parameter)
    - test: green — `swift test -Xswiftc -warnings-as-errors`: 240 tests in 32 suites passed; swiftlint 0
    - commit: changed — 78d82e1
    - review: clean — 0 findings
  timestamp: 2026-09-23T21:01:38.601060+00:00
depends_on:
- 01M376GGK2RB6A3XA1PSVRGW9K
- 01M376GQ5AB99BJYWHWW67DVCR
- 01M376J35YTN5ZDS4GF89F9TAG
position_column: done
position_ordinal: '9580'
title: 'skills: preload into the instructions of a run'
---
## What
Plan.md §5 (`skills:` preload), §8 step 3.

- In `Sources/FoundationModelsAgents/Run/AgentRun.swift` (or a new `AgentRun+Instructions.swift`), at run start, for each name in `definition.skills` call `environment.skills.call(id:)` and append the rendered body to the instructions, after the agent body, in the order of the key.
- An unknown skill, or a skill that is not model-visible, is a warning and is skipped. Add these warnings to `runner.catalog()` diagnostics too (look up the names in `SkillsRegistry` listing).
- The `skills` tool is one entry of the `ToolCatalog` and follows the normal tool rules; the preload does not add the tool.

## Acceptance Criteria
- [x] An agent with `skills: [review]` has the rendered `review` body in its session instructions, after its own body.
- [x] Two skills appear in the order of the key.
- [x] An unknown skill name gives a warning in `runner.catalog()` and the run still starts.
- [x] A skill with `disable-model-invocation: true` is skipped with a warning.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/SkillsPreloadTests.swift` with a `SkillsRegistry` over `Examples/agent-library/defaults` and the scripted profile.
- [x] Run `swift test --filter SkillsPreloadTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.