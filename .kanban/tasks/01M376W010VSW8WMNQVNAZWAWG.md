---
assignees:
- claude-code
depends_on:
- 01M376D9AJZB96ZHWEEXGW96QC
position_column: todo
position_ordinal: 9b80
title: CI workflow and CIWorkflowTests
---
## What
Plan.md §11. Connect the package to the shared CI of the organization.

- Create `.github/workflows/ci.yml` that calls `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main`, as `../FoundationModelsSkills/.github/workflows/ci.yml` does: triggers `push` to `main`, `pull_request`, `workflow_dispatch`; concurrency group `ci-${{ github.ref }}`; one job with no `steps:` of its own.
- Create `Tests/FoundationModelsAgentsTests/CIWorkflowTests.swift` with the method of Skills `CIWorkflowTests`.

## Acceptance Criteria
- [ ] `ci.yml` delegates to the shared workflow with no `steps:` of its own.
- [ ] `CIWorkflowTests` checks the `uses:` target, the triggers, and the concurrency group, and passes.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/CIWorkflowTests.swift`.
- [ ] Run `swift test --filter CIWorkflowTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.