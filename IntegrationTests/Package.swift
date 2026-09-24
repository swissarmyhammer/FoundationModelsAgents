// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// The integration suites of plan.md §15 are in this nested package, as in the
// peer packages (FoundationModelsRouter, FoundationModelsMultitool). The
// package boundary is the split between the unit tests and the integration
// tests:
//
// - `swift test` at the repository root runs only the unit tests. The root
//   manifest names no target of this package, thus the root build cannot see
//   it. No `--skip`, no name filter, and no environment variable is necessary.
// - `cd IntegrationTests && swift test` (or
//   `swift test --package-path IntegrationTests`) runs the integration
//   suites. Each suite uses real `mlx-community` models, and some suites use
//   the network.
//
// No source of this package reads an environment variable to select or skip
// a test, and no source may start to do so. `IntegrationPackageTests` in the
// root package pins this.
//
// SwiftPM manifests cannot import each other, thus the dependency pins below
// repeat the pins of `../Package.swift`. Each URL and each requirement must be
// the same as in the root manifest, because this package depends on the root
// package by path, and two different pins do not resolve.

/// The name of the package under test. It is also the name of the folder
/// `..`, which is the identity of the path dependency.
let rootPackageName = "FoundationModelsAgents"

/// The name of the integration test target.
let integrationTargetName = "AgentsIntegrationTests"

/// The GitHub organization URL for the swissarmyhammer sibling packages. It
/// is the same as `swissArmyHammerOrg` of the root manifest.
let swissArmyHammerOrg = "git@github.com:swissarmyhammer/"

/// The name of the FoundationModelsRouter package.
let routerPackageName = "FoundationModelsRouter"

/// The name of the FoundationModelsExtras package.
let extrasPackageName = "FoundationModelsExtras"

/// The name of the FoundationModelsSkills package.
let skillsPackageName = "FoundationModelsSkills"

/// The name of the controlled fork of mlx-swift-lm.
let mlxPackageName = "mlx-swift-lm"

/// The name of the Hugging Face Hub client package.
let huggingFacePackageName = "swift-huggingface"

/// The name of the Swift Transformers tokenizer package.
let transformersPackageName = "swift-transformers"

/// The products that the integration test target links.
let integrationDependencies: [Target.Dependency] = [
    // The library under test.
    .product(name: rootPackageName, package: rootPackageName),
    // `Router`, `ProfileDefinition`, `LanguageModelProfile`, and
    // `LiveModelLoader`.
    .product(name: routerPackageName, package: routerPackageName),
    // `MetalLibraryTestBootstrap`, which the live profile reads before the
    // first resolve.
    .product(name: "\(routerPackageName)TestSupport", package: routerPackageName),
    // `DotfolderStack` for the local layer.
    .product(name: extrasPackageName, package: extrasPackageName),
    // `MarketplaceSource` and `MarketplaceStore`.
    .product(name: "Marketplace", package: extrasPackageName),
    // `GitFixtureRepository` and `MarketplaceStoreFixture`.
    .product(name: "MarketplaceFixtures", package: extrasPackageName),
    // `SkillsRegistry` for the environment of each run.
    .product(name: skillsPackageName, package: skillsPackageName),
    // The live model loader, as in the `agents-demo` example: the
    // `#hubDownloader()` and `#huggingFaceTokenizerLoader()` macros expand to
    // code that uses `HuggingFace.HubClient` and `Tokenizers.AutoTokenizer`.
    .product(name: "MLXHuggingFace", package: mlxPackageName),
    .product(name: "MLXLMCommon", package: mlxPackageName),
    .product(name: "HuggingFace", package: huggingFacePackageName),
    .product(name: "Tokenizers", package: transformersPackageName)
]

/// The integration suites of `FoundationModelsAgents`.
let package = Package(
    name: "IntegrationTests",
    // macOS 27 only, the same floor as `../Package.swift`.
    platforms: [
        .macOS("27.0")
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "\(swissArmyHammerOrg)\(routerPackageName).git", branch: "main"),
        .package(url: "\(swissArmyHammerOrg)\(extrasPackageName).git", branch: "main"),
        .package(url: "\(swissArmyHammerOrg)\(skillsPackageName).git", branch: "main"),
        .package(url: "https://github.com/swissarmyhammer/\(mlxPackageName)", branch: "stable"),
        .package(url: "https://github.com/huggingface/\(huggingFacePackageName)", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/\(transformersPackageName)", from: "1.3.0")
    ],
    targets: [
        // The live suites. Each suite resolves the real profile of
        // `LiveProfile` or reads a real marketplace on the network. This
        // target is only in this package, thus a root `swift test` cannot
        // see it.
        .testTarget(
            name: integrationTargetName,
            dependencies: integrationDependencies,
            path: "Tests/\(integrationTargetName)"
        )
    ]
)
