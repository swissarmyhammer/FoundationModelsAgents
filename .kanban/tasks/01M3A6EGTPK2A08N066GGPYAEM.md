---
assignees:
- claude-code
depends_on:
- 01M3A6DQW7S7GYSPTDY3QHG0XH
- 01M3A6DZBWW4SMKGJCA3H1KBYF
position_column: todo
position_ordinal: 8d80
title: 'After the Router generation queue ships: remove the different-slot workaround and update the Router revision'
---
## What
BLOCKED outside this board: start only after the FoundationModelsRouter session reports that its task `^44y6ba4` (the agents case of the generation queue) is done and pushed. The Router work has the tag `generation-queue` on the Router board. Remove the tag `waits-on-router` from this task when that happens.

- `Package.resolved` is ignored by git. Both packages depend on the Router with `branch: "main"`, and on `mlx-swift-lm` directly with `branch: "stable"`. Run `swift package update` at the root and in `IntegrationTests/`, and check that both resolve the same Router revision, one that holds `^44y6ba4`. (Now the root resolves `d19f64a` and `IntegrationTests/` resolves `bbad3ce`.)
- Remove the different-slot workaround in the tests: gated runs no longer need to be on different slots. Where two runs must share a queue, give their slots the same model reference and the same context (the queue key is the pool entry: the reference plus the role, and the role holds the context size).
- Add a scripted test for the agents case: a parent and a child on the same model; the parent waits in a tool; the child completes.
- Remove from the tests and the docs any text that says a turn holds the model for its whole length.

## Acceptance Criteria
- [ ] The root and `IntegrationTests/` resolve the same Router revision, and it holds `^44y6ba4`.
- [ ] No test puts a run on a different slot only to avoid the lock.
- [ ] A parent and a child on the same model both make progress while the parent waits in a tool.
- [ ] The root and the integration suites pass.

## Tests
- [ ] A new case in `NestedRunTests.swift` for the same-model parent and child.
- [ ] Run `swift test -Xswiftc -warnings-as-errors` and `cd IntegrationTests && swift test`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #waits-on-router