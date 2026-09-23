---
assignees:
- claude-code
depends_on:
- 01M376DS6RBPHB0AEP6604D8Z7
position_column: todo
position_ordinal: 9c80
title: 'Guard tests: no standard output, no DotfolderStack extension, no code-mode conformance'
---
## What
The other guard tests of plan.md §15. Use `SwiftSourceScan` and the method of the Skills tests of the same names.

- `Tests/FoundationModelsAgentsTests/NoStandardOutWriteTests.swift`: no `print(` and no standard-output write in the library (the Skills rule).
- `Tests/FoundationModelsAgentsTests/NoDotfolderStackExtensionTests.swift`: the Skills rule only: the marker `extension DotfolderStack` followed by a character that is not a letter or a digit.
- `Tests/FoundationModelsAgentsTests/NoCodeModeConformanceTests.swift`: no `OperationDescribing` and no `ForkableTool` in the library (plan.md §9.5).

## Acceptance Criteria
- [ ] Each of the three tests passes on the scaffold.
- [ ] Each rule finds its forbidden line in an in-memory list of lines.

## Tests
- [ ] The three test files above.
- [ ] Run `swift test --filter "NoStandardOut|NoDotfolderStack|NoCodeMode"`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.