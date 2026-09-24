import Foundation
import Testing

/// Guards the split between the unit tests and the integration tests
/// (plan.md §15).
///
/// The integration tests are in the nested `IntegrationTests/` package, as in
/// the peer packages. The package boundary is the split:
///
/// - The root manifest names no integration target and no path in
///   `IntegrationTests/`. Thus a root `swift test` does not build the nested
///   package.
/// - The nested manifest depends on the root package by path. Thus
///   `cd IntegrationTests && swift test` tests this checkout.
/// - No Swift source of the nested package reads an environment variable.
///   Thus no environment variable selects or skips an integration test.
///
/// The walk reads `IntegrationTests/Tests` and the nested manifest, and not
/// the whole `IntegrationTests/` folder: its `.build/` folder holds the Swift
/// sources of each dependency.
@Suite("Integration package")
struct IntegrationPackageTests {
    /// The folder of the nested package, relative to the package root.
    private static let integrationPackageDirectory = "IntegrationTests"

    /// The folder of the test targets of the nested package, relative to the
    /// package root.
    private static let integrationTestsDirectory = integrationPackageDirectory + "/Tests"

    /// The file name of a SwiftPM manifest.
    private static let manifestName = "Package.swift"

    /// The line of the nested manifest that depends on the root package.
    private static let rootPackageDependency = #".package(path: "..")"#

    /// The names that read or change an environment variable. No line of code
    /// in the nested package may hold one of them.
    private static let environmentNames = ["ProcessInfo", "getenv", "setenv", "unsetenv", "environ"]

    @Test("the root manifest names no integration target and no path in IntegrationTests/")
    func rootManifestDoesNotNameTheIntegrationPackage() throws {
        let lines = try Self.manifestLines(in: PackageRoot.directory)
        let offenders = SwiftSourceScan.lineNumbers(in: lines) { line in
            !SwiftSourceScan.isComment(line) && line.contains(Self.integrationPackageDirectory)
        }

        #expect(
            offenders.isEmpty,
            """
            The root Package.swift must not name \(Self.integrationPackageDirectory). The package boundary \
            keeps the integration tests out of a root swift test; found on the lines: \(offenders)
            """)
    }

    @Test("the nested manifest depends on the root package by path")
    func nestedManifestDependsOnTheRootPackage() throws {
        let lines = try Self.manifestLines(in: Self.integrationPackageFolder)
        let dependsOnRoot = lines.contains { line in
            !SwiftSourceScan.isComment(line) && line.contains(Self.rootPackageDependency)
        }

        #expect(dependsOnRoot, "IntegrationTests/Package.swift must hold \(Self.rootPackageDependency).")
    }

    @Test(arguments: [
        "let value = ProcessInfo.processInfo.environment[\"AGENTS_INTEGRATION\"]",
        "if getenv(\"RUN_LIVE\") == nil {",
        "setenv(\"RUN_LIVE\", \"1\", 1)",
        "    unsetenv(\"RUN_LIVE\")",
        "let names = environ"
    ])
    func aLineThatReadsTheEnvironmentIsReported(line: String) {
        #expect(Self.readsTheEnvironment(line))
    }

    @Test(arguments: [
        "// No test reads ProcessInfo.processInfo.environment.",
        "/// The suite never calls getenv.",
        "let environment = AgentEnvironment(profile: profile, skills: skills)",
        "let fixture = try MarketplaceStoreFixture(sources: sources)"
    ])
    func aLineThatReadsNoEnvironmentVariableIsNotReported(line: String) {
        #expect(!Self.readsTheEnvironment(line))
    }

    @Test("no Swift source of the integration package reads an environment variable")
    func noIntegrationSourceReadsTheEnvironment() throws {
        let testOffenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.integrationTestsDirectory, matching: Self.readsTheEnvironment)
        let manifestOffenders = SwiftSourceScan.lineNumbers(
            in: try Self.manifestLines(in: Self.integrationPackageFolder),
            matching: Self.readsTheEnvironment)

        #expect(
            testOffenders.isEmpty && manifestOffenders.isEmpty,
            """
            No source of the integration package may read an environment variable to select or skip a \
            test; found: \(testOffenders), and on the lines \(manifestOffenders) of the manifest
            """)
    }

    /// Tells whether one line of code reads or changes an environment
    /// variable.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line is code and holds one of
    ///   ``environmentNames`` as a full token.
    private static func readsTheEnvironment(_ line: String) -> Bool {
        !SwiftSourceScan.isComment(line)
            && environmentNames.contains { SwiftSourceScan.holds(token: $0, in: line) }
    }

    /// The folder of the nested package.
    private static var integrationPackageFolder: URL {
        PackageRoot.directory.appendingPathComponent(integrationPackageDirectory, isDirectory: true)
    }

    /// Reads the lines of a manifest.
    ///
    /// - Parameter folder: The folder of the manifest.
    /// - Returns: Each line of the manifest.
    /// - Throws: An error when the file cannot be read.
    private static func manifestLines(in folder: URL) throws -> [String] {
        let text = try String(contentsOf: folder.appendingPathComponent(manifestName), encoding: .utf8)
        return text.components(separatedBy: .newlines)
    }
}
