---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3n2pytj30g0fhmn5vw08m2a
  text: |-
    Research and implementation:
    - The code: `AgentDefinitionRules.nameFindings` gives a warning when `name` is absent or not equal to the file name. `AgentRunner.start(_:prompt:)` is `async throws(AgentRunnerError)`. `AgentRun.result()` is `async throws`.
    - The §4.2 tier cell also said that `description` is required. §4.3 makes an absent or empty `description` a warning (the agent is then not model-visible). The new cell states both rules, so §4.2 agrees with §4.3.
    - Discovery: a scratch file type-checks with `swiftc -swift-version 6 -warnings-as-errors` in BOTH forms: `async let a = runner.start(...).result()` and `async let a = try await runner.start(...).result()`. The `async let` initializer covers `try` and `await` without the words. The place that must have `try await` is the read of `a`. The §9.3 example now writes the explicit form and the read: `let reviewA = try await a`.
    - New test file `Tests/FoundationModelsAgentsTests/PlanTextTests.swift` (suite "plan.md text"): 4 claims that the plan must hold, 2 old texts that it must not hold. RED: 6 issues before the plan edit. GREEN after the edit.
    - `swift build -Xswiftc -warnings-as-errors`: Build complete, no compiler warning. `swift test -Xswiftc -warnings-as-errors`: 384 tests in 54 suites passed. "Run model wording", "README.md text" and "plan.md text" pass. The only warnings in the output are SwiftPM manifest cache "disk I/O error" lines, not compiler warnings.
  timestamp: 2026-09-28T22:38:33.298404+00:00
- actor: claude-code
  id: 01m3n2q0das3jng7frr8eppkz1
  text: |-
    ### implement — changed
    - evidence: 2 files — plan.md (§4.2 tier cell, §9.3 fan-out example), Tests/FoundationModelsAgentsTests/PlanTextTests.swift (new, 6 test cases); swift build -Xswiftc -warnings-as-errors: Build complete; swift test -Xswiftc -warnings-as-errors: 384 tests in 54 suites passed, 0 failures
    - next: /review
  timestamp: 2026-09-28T22:38:34.922193+00:00
- actor: claude-code
  id: 01m3n2v2nrh949x59btjg3kdqr
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (f39464e). 0 findings (confirmed 0, refuted 0, attempted 7, failed 0). Validators examined PlanTextTests.swift. No validator matches plan.md. The .kanban/ files are excluded by .reviewignore.
    - next: none. The task is in done.
  timestamp: 2026-09-28T22:40:48.312634+00:00
- actor: claude-code
  id: 01m3n2v9z5esksc31ta541taxw
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — plan.md §4.2 and §9.3, new PlanTextTests.swift
    - test: green — swift test -Xswiftc -warnings-as-errors, 384 tests in 54 suites passed; swiftlint 0 issues
    - commit: f39464e
    - review: clean — 0 findings
  timestamp: 2026-09-28T22:40:55.781694+00:00
depends_on:
- 01M3FMWXRW3637CJ74T7F7Z6QA
position_column: done
position_ordinal: b980
title: 'plan.md: the §4.2 name tier and the §9.3 example'
---
## What
Two text errors in `plan.md` that ^9ndk9rh found:
- The §4.2 tier table says that `name` is "required". §4.3 and the code (`AgentDefinitionRules.nameFindings`) make a missing or different `name` a warning, and the file loads, because the file name is the id. Correct the table.
- The §9.3 example `async let a = runner.start(...).result()` has no `try await`. `start` and `result()` are `async throws`. Correct the example so that it compiles as Swift.

## Acceptance Criteria
- [x] §4.2 agrees with §4.3 and with `AgentDefinitionRules`.
- [x] The §9.3 example has the correct `try await`.

## Tests
- [x] Add the two corrected statements as claims in `Tests/FoundationModelsAgentsTests/ReadmeTextTests.swift` or a new plan-text test, and see them fail first.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.