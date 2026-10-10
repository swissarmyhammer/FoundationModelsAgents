---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4jy0yywcny7devmp9gy6bxr
  text: |-
    Done after the N=10 measurements of ^vhhdw1h (those used the 16abef2d pin, so the counts compare).
    - `swift package update FoundationModelsRouter` at the root and in IntegrationTests: both Package.resolved files now pin Router main dc642256bcd2cbb1c47f98ad7dad4c49533af578.
    - `Run/AgentRunProgress.swift` and `Run/AgentRun+TurnLimit.swift`: `case .toolInvocation(let record, _)`.
    - `Run/AgentRun+TurnLimit.swift` doc link: ``SessionEvent/toolInvocation(_:toolCallID:)``.
    - `Examples/agents-demo/DemoModes.swift` (`lines(for:)`, an exhaustive switch with no default): adds `.toolDisplay` to the cases that give no line.
    - The test events in `MaxTurnsTests+Counter.swift` and `AgentRunProgressTests.swift` build `.toolInvocation(record)`; the new `toolCallID` has the default `nil`, thus they compile with no change. I did not edit them.

    ### implement — changed
    - evidence: `swift test` 497 tests in 67 suites passed; `swift build --package-path IntegrationTests --build-tests` exit 0; both against Router main dc642256 (one SwiftPM "missing creator for mutated node" warning for the mlx Cmlx.bundle, also present before). Files: Sources/FoundationModelsAgents/Run/AgentRunProgress.swift, Sources/FoundationModelsAgents/Run/AgentRun+TurnLimit.swift, Examples/agents-demo/DemoModes.swift (Package.resolved files are not tracked by git).
    - next: /review. No live measurement was run against Router main.
  timestamp: 2026-10-10T12:53:51.196941+00:00
position_column: done
position_ordinal: d080
title: 'Adopt Router main: SessionEvent.toolInvocation has two associated values'
---
## What

FoundationModelsRouter main (dc642256, commit 7f20163b "join the SDK tool-call id with the run completion token") changed `SessionEvent.toolInvocation` to `case toolInvocation(ToolInvocationRecord, toolCallID: String? = nil)`. FoundationModelsAgents does not compile against that revision:

- `Sources/FoundationModelsAgents/Run/AgentRunProgress.swift` (`apply(_:)`): `if case .toolInvocation(let record) = event` binds a tuple. The compiler gives "value of tuple type ... has no member 'closedAt'".
- `Sources/FoundationModelsAgents/Run/AgentRun+TurnLimit.swift`: the same pattern, and the doc reference ``SessionEvent/toolInvocation(_:)``.
- `Tests/FoundationModelsAgentsTests/MaxTurnsTests+Counter.swift` and `AgentRunProgressTests.swift` make `.toolInvocation(...)` events.

Router main also adds `SessionEvent.toolDisplay`.

CI resolves main fresh, thus CI fails until this change lands.

## Work

1. Bind the record and ignore the tool-call id (`case .toolInvocation(let record, _)`), or use the id where it helps.
2. Update the doc reference and the tests.
3. `swift package update` at the root and in `IntegrationTests`, then `swift test` and `swift build --package-path IntegrationTests --build-tests`.

## Acceptance criteria

- [ ] The package builds and `swift test` passes against Router main.
- [ ] The IntegrationTests package builds against Router main.