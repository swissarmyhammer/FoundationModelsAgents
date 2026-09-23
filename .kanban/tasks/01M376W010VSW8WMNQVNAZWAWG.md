---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m379efsy4wg031r5k7ttw62q
  text: |-
    Research: the Skills `CIWorkflowTests` reads the file through its `FixtureLibrary`. This package has no such helper yet, thus the new suite finds the package root from `#filePath` (3 levels up). The Skills suite uses `guard` and pins `test-skip`/`integration-filter` inputs. This package has no live-model suite yet, thus `ci.yml` passes no `with:` inputs; task ^kk75 (IntegrationTests package, gate, CI inputs) adds them. No `guard` in the new test file.

    TDD: the 4 tests failed first (ci.yml not found), then passed after ci.yml was written. swiftlint on the test file: 0 violations (a trailing comma was removed).

    ### implement — changed
    - evidence: 2 files — .github/workflows/ci.yml, Tests/FoundationModelsAgentsTests/CIWorkflowTests.swift; `swift test --filter CIWorkflowTests` 4/4 pass
    - next: test
  timestamp: 2026-09-23T14:06:53.758528+00:00
- actor: claude-code
  id: 01m379fkszmchygc182kkjnkzh
  text: |-
    ### test — green
    - evidence: `swift build --build-tests -Xswiftc -warnings-as-errors` clean (only the known mlx-swift "missing creator" build-system note); `swift test` — 12 tests in 3 suites passed, 0 failed, 0 skipped; `swiftlint lint --quiet Sources Tests Examples` 0 violations. Note: default swiftlint reports 6 trailing_comma warnings in Package.swift. They are on main before this task and not in this diff.
    - next: commit
  timestamp: 2026-09-23T14:07:30.623395+00:00
- actor: claude-code
  id: 01m379jwexzqa2t66cza5f1keq
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 0 confirmed, 0 refuted; 7 validator runs attempted, 0 failed; 2 files reviewed (.kanban excluded by .reviewignore)
    - next: done

    ### finish iteration 1 — clean
    - implement: changed — .github/workflows/ci.yml, Tests/FoundationModelsAgentsTests/CIWorkflowTests.swift
    - test: green — swift test 12 passed, 0 failed, 0 skipped; build -warnings-as-errors clean; swiftlint Sources Tests Examples 0 violations
    - commit: changed — e808997 ci: delegate CI to the shared swift-ci workflow; add CIWorkflowTests
    - review: clean — 0 findings
  timestamp: 2026-09-23T14:09:17.789296+00:00
depends_on:
- 01M376D9AJZB96ZHWEEXGW96QC
position_column: done
position_ordinal: '8280'
title: CI workflow and CIWorkflowTests
---
## What
Plan.md §11. Connect the package to the shared CI of the organization.

- Create `.github/workflows/ci.yml` that calls `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main`, as `../FoundationModelsSkills/.github/workflows/ci.yml` does: triggers `push` to `main`, `pull_request`, `workflow_dispatch`; concurrency group `ci-${{ github.ref }}`; one job with no `steps:` of its own.
- Create `Tests/FoundationModelsAgentsTests/CIWorkflowTests.swift` with the method of Skills `CIWorkflowTests`.

## Acceptance Criteria
- [x] `ci.yml` delegates to the shared workflow with no `steps:` of its own.
- [x] `CIWorkflowTests` checks the `uses:` target, the triggers, and the concurrency group, and passes.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/CIWorkflowTests.swift`.
- [x] Run `swift test --filter CIWorkflowTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.