// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The name of the package, the library product, and the library target.
///
/// One constant keeps the name the same in each declaration below.
let packageName = "FoundationModelsAgents"

/// The name of the unit test target.
let testTargetName = packageName + "Tests"

/// The name of the example executable (plan.md §11, §13).
let demoTargetName = "agents-demo"

/// The GitHub organization URL for the swissarmyhammer sibling packages.
///
/// Each sibling is a remote dependency on the `main` branch, never a local
/// `path:` dependency. The shared CI workflow checks out only this repository,
/// thus a `path:` dependency would not exist there. A remote reference also
/// prevents the SwiftPM "Conflicting identity" warning, which occurs when one
/// package is reached by path here and by URL from a different package.
let swissArmyHammerOrg = "git@github.com:swissarmyhammer/"

/// The product dependencies of the library target (plan.md §11).
///
/// The example executable and the test target use the same list, thus the
/// three lists cannot become different.
let commonDependencies: [Target.Dependency] = [
    // `LanguageModelProfile`, `RoutedSession`, `ToolContext`, and the
    // recording types.
    .product(name: "FoundationModelsRouter", package: "FoundationModelsRouter"),
    // `DotfolderStack`, `FrontmatterDocumentStack`, `DotfolderWatcher`,
    // `StenciledDotfolderStack`, `QuarantinedText`, `AgentsMd`, and the
    // slash-command vocabulary.
    .product(name: "FoundationModelsExtras", package: "FoundationModelsExtras"),
    // `MarketplaceLayerProviding`, `MarketplaceLayer`, and
    // `MarketplaceProvenance`.
    .product(name: "Marketplace", package: "FoundationModelsExtras"),
    // `OperationTool`, `@Operation`, and `OperationResolver`.
    .product(name: "Operations", package: "FoundationModelsExtras"),
    // `OperationCLIDriver` for the dual-use CLI.
    .product(name: "OperationsCLI", package: "FoundationModelsExtras"),
    // `SkillsRegistry` and `SkillListing`.
    .product(name: "FoundationModelsSkills", package: "FoundationModelsSkills"),
    // `AgentFrontmatter.decode` reads YAML with Yams.
    .product(name: "Yams", package: "Yams"),
    // Run ids.
    .product(name: "ULID", package: "ULID.swift"),
]

/// The test-only products. Only the test target links them.
///
/// The library links none of them, thus a host gets no test code.
let testOnlyDependencies: [Target.Dependency] = [
    // The scripted test support of the Router.
    .product(name: "FoundationModelsRouterTestSupport", package: "FoundationModelsRouter"),
    // `MarketplaceStoreFixture`, `GitFixtureRepository`, `ManualClock`, and
    // the other marketplace fixtures.
    .product(name: "MarketplaceFixtures", package: "FoundationModelsExtras"),
]

/// The `FoundationModelsAgents` SwiftPM package.
///
/// One library target, one example executable, and one unit test target
/// (plan.md §11). The layers of plan.md §3 are types in the one library
/// target, not separate modules.
let package = Package(
    name: packageName,
    // macOS 27 only. FoundationModels v2 needs macOS 27, and each sibling
    // package declares the same floor. The string form states macOS 27 under
    // tools 6.2.
    platforms: [
        .macOS("27.0"),
    ],
    products: [
        .library(name: packageName, targets: [packageName]),
    ],
    dependencies: [
        .package(url: "\(swissArmyHammerOrg)FoundationModelsRouter.git", branch: "main"),
        .package(url: "\(swissArmyHammerOrg)FoundationModelsExtras.git", branch: "main"),
        .package(url: "\(swissArmyHammerOrg)FoundationModelsSkills.git", branch: "main"),
        // The same exact pin as the Yams pin of `FoundationModelsExtras`.
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        // The same pin as the ULID.swift pin of `FoundationModelsRouter`.
        .package(url: "https://github.com/yaslab/ULID.swift.git", from: "1.3.1"),
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: commonDependencies
        ),
        // The example of plan.md §13. It is in the root manifest, thus one
        // `swift build` builds the library and the example.
        .executableTarget(
            name: demoTargetName,
            dependencies: [.byName(name: packageName)] + commonDependencies,
            path: "Examples/\(demoTargetName)"
        ),
        .testTarget(
            name: testTargetName,
            dependencies: [.byName(name: packageName)] + commonDependencies
                + testOnlyDependencies
        ),
    ]
)
