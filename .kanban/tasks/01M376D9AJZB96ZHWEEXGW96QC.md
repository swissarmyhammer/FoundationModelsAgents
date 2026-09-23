---
assignees:
- claude-code
position_column: todo
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
- [ ] `swift build` succeeds, and builds the library and `agents-demo`.
- [ ] `swift test` runs and passes.
- [ ] The test target imports `FoundationModelsRouterTestSupport` and `MarketplaceFixtures`; the library does not.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/PackageSmokeTests.swift`: the module imports, and `FoundationModelsAgents` exists.
- [ ] Run `swift build && swift test`. Expected: success.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.