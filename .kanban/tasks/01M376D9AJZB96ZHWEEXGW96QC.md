---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m377q9qy5nba4krfq4sppens
  text: 'Research: `.gitignore` and `.reviewignore` exist at the repo root already. `.gitignore` has `.build/` and `.swiftpm/`. `.reviewignore` has `.kanban/`, as in Skills. No change is necessary for them. The Router pins ULID.swift with `from: "1.3.1"` (https://github.com/yaslab/ULID.swift.git, product `ULID`). Extras pins Yams `exact: "6.2.2"`. The Skills manifest keeps the org URL in `swissArmyHammerOrg` and splits `commonDependencies` from `testOnlyDependencies`. This manifest uses the same shape.'
  timestamp: 2026-09-23T13:36:45.310465+00:00
- actor: claude-code
  id: 01m377whpf4pp7bchsb8dvn4dq
  text: |-
    ### implement — changed
    - evidence: 5 files — Package.swift, Sources/FoundationModelsAgents/FoundationModelsAgents.swift, Examples/agents-demo/main.swift, Tests/FoundationModelsAgentsTests/PackageSmokeTests.swift, .gitignore (adds `Package.resolved`, as in Skills and Router). Red first: `swift build` failed with no library sources. Then `swift build` passed, and `swift test` ran 3 tests in 1 suite, all pass. `swift run agents-demo` prints the usage. The only build warnings come from the third-party `mlx-swift` checkout and the build system (`missing creator for mutated node`), not from this package.
    - note: Yams and ULID are in the product list of the library target, because SwiftPM warns about a package dependency that no target uses.
    - next: test
  timestamp: 2026-09-23T13:39:37.295711+00:00
- actor: claude-code
  id: 01m377zps9z352gsmhsgrfktjk
  text: |-
    ### test — green
    - evidence: `swift build --build-tests -Xswiftc -warnings-as-errors` passes. `swift test`: 3 tests in 1 suite pass, 0 fail, 0 skipped. The build system writes one warning, `missing creator for mutated node: ... mlx-swift_Cmlx.bundle/Contents/MacOS`. It comes from the third-party `mlx-swift` dependency of the Router. A `swift build` in `../FoundationModelsRouter` alone writes the same warning, so no source in this package causes it.
    - next: commit
  timestamp: 2026-09-23T13:41:20.809991+00:00
position_column: doing
position_ordinal: '80'
title: Scaffold the Swift package and the namespace
---
## What
Make the package skeleton that all other tasks build on (plan.md §11).

- Create `Package.swift`: swift-tools-version 6.2, `.macOS("27.0")`, package name `FoundationModelsAgents`.
  - Library target `FoundationModelsAgents` and product of the same name.
  - Executable target `agents-demo` at `Examples/agents-demo` (a `main.swift` that prints the usage only, for now).
  - Test target `FoundationModelsAgentsTests`.
  - Remote dependencies on `main`, with the org URL `git@github.com:swissarmyhammer/` in one constant, as in `../FoundationModelsSkills/Package.swift`: `FoundationModelsRouter` (products `FoundationModelsRouter`; `FoundationModelsRouterTestSupport` for the test target only), `FoundationModelsExtras` (products `FoundationModelsExtras`, `Marketplace`, `Operations`, `OperationsCLI`; `MarketplaceFixtures` for the test target only), `FoundationModelsSkills`, Yams `exact: "6.2.2"` (the Extras pin), ULID.swift (the Router's pin).
- Create `Sources/FoundationModelsAgents/FoundationModelsAgents.swift`: a namespace `enum FoundationModelsAgents` with a doc comment that states the layers of plan.md §3.
- Create `.gitignore` (`.build/`, `.swiftpm/`) and `.reviewignore` as in Skills.
- Do not use the name `AgentSession` for a type (it is a protocol of `FoundationModelsMetadataRegistry`, plan.md §11).

## Acceptance Criteria
- [x] `swift build` succeeds, and builds the library and `agents-demo`.
- [x] `swift test` runs and passes.
- [x] The test target imports `FoundationModelsRouterTestSupport` and `MarketplaceFixtures`; the library does not.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/PackageSmokeTests.swift`: the module imports, and `FoundationModelsAgents` exists.
- [x] Run `swift build && swift test`. Expected: success.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.