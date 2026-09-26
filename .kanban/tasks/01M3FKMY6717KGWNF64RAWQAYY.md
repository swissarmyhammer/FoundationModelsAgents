---
assignees:
- claude-code
depends_on:
- 01M3FMWXRW3637CJ74T7F7Z6QA
position_column: todo
position_ordinal: 8f80
title: 'plan.md: the §4.2 name tier and the §9.3 example'
---
## What
Two text errors in `plan.md` that ^9ndk9rh found:
- The §4.2 tier table says that `name` is "required". §4.3 and the code (`AgentDefinitionRules.nameFindings`) make a missing or different `name` a warning, and the file loads, because the file name is the id. Correct the table.
- The §9.3 example `async let a = runner.start(...).result()` has no `try await`. `start` and `result()` are `async throws`. Correct the example so that it compiles as Swift.

## Acceptance Criteria
- [ ] §4.2 agrees with §4.3 and with `AgentDefinitionRules`.
- [ ] The §9.3 example has the correct `try await`.

## Tests
- [ ] Add the two corrected statements as claims in `Tests/FoundationModelsAgentsTests/ReadmeTextTests.swift` or a new plan-text test, and see them fail first.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.