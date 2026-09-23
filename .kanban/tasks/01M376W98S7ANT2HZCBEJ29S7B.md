---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37a97dwvyvk20erra5jsarf
  text: |-
    ### implement — changed
    - evidence: 5 files — Tests/FoundationModelsAgentsTests/NoStandardOutWriteTests.swift, NoDotfolderStackExtensionTests.swift, NoCodeModeConformanceTests.swift (new); Support/SwiftSourceScan.swift (new shared helpers `isComment(_:)` and `holds(token:in:)`), SwiftSourceScanTests.swift (tests of the helpers).
    - discoveries: the Skills reference uses `guard` in a test file; this package forbids `guard` in tests, thus the token check lives in SwiftSourceScan with no `guard`. The comment check and the token check are shared by NoStandardOut and NoCodeMode, thus no copy. The NoCodeMode rule skips comment lines, so a doc comment can tell that AgentsTool does not conform (plan.md §9.5). NoStandardOut walks `Sources` and `Examples/agents-demo`.
    - next: test
  timestamp: 2026-09-23T14:21:29.916941+00:00
depends_on:
- 01M376DS6RBPHB0AEP6604D8Z7
position_column: doing
position_ordinal: '80'
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