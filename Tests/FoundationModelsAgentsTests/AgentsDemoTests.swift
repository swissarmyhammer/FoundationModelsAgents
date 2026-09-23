import Foundation
import FoundationModelsAgents
import Testing

@testable import agents_demo

/// The contract of `Examples/agents-demo` (plan.md §13).
///
/// The first case runs the built `agents-demo` binary, as a user does. The
/// other cases call the function of each mode directly, with no process. The
/// test target depends on the example target, thus `swift test` builds the
/// binary first and `@testable import agents_demo` gives the mode functions.
@Suite("agents-demo")
struct AgentsDemoTests {
    /// The name of the built example binary.
    private static let binaryName = "agents-demo"

    /// The exit code of a run that ends with no failure.
    private static let successExitCode: Int32 = 0

    /// The flag that no mode of the example has.
    private static let unknownFlag = "--no-such-mode"

    /// The id of the agent that the watch case adds to the copy of the
    /// library.
    private static let addedAgentID = "added-agent"

    /// The path of the added agent file, relative to the library root.
    private static let addedAgentPath = "defaults/agents/\(addedAgentID).md"

    /// The text of the added agent file.
    private static let addedAgentText = """
        ---
        name: \(addedAgentID)
        description: An agent that the watch case adds.
        ---
        Do the added work.
        """

    /// The text that opens the first line of each reload report.
    private static let reportPrefix = "reload: "

    /// The provenance line of each agent of the fixture marketplace.
    private static let marketplaceLines = [
        "doc-writer: marketplace docs-tools",
        "security-reviewer: marketplace code-tools"
    ]

    // MARK: - The built binary

    @Test("with no mode, the binary writes the usage and exits 0")
    func noModeWritesTheUsage() throws {
        let result = try Self.run(arguments: [])

        #expect(result.exitCode == Self.successExitCode)
        #expect(result.output == AgentsDemoUsage.text + "\n")
    }

    @Test("with an unknown mode, the binary writes the usage and fails")
    func unknownModeFails() throws {
        let result = try Self.run(arguments: [Self.unknownFlag])

        #expect(result.exitCode != Self.successExitCode)
        #expect(result.output.contains(Self.unknownFlag))
        #expect(result.output.contains(AgentsDemoUsage.text))
    }

    // MARK: - The mode parse

    @Test("each flag gives its mode")
    func eachFlagGivesItsMode() {
        #expect(AgentsDemoMode(arguments: []) == .usage)
        #expect(AgentsDemoMode(arguments: [AgentsDemoMode.watchFlag]) == .watch)
        #expect(AgentsDemoMode(arguments: [AgentsDemoMode.marketplaceFlag]) == .marketplace)
        #expect(AgentsDemoMode(arguments: [Self.unknownFlag]) == .unknown(Self.unknownFlag))
    }

    // MARK: - --watch

    @Test("the watch mode writes a report after a file of the library changes", .timeLimit(.minutes(1)))
    func watchModeWritesAReportAfterAChange() async throws {
        let library = try TemporaryLayer.copy(of: FixtureLibrary.root)
        defer { try? library.delete() }
        let registry = AgentRegistry(stack: AgentsDemoLibrary.stack(libraryRoot: library.root), watch: true)
        let (lines, continuation) = AsyncStream.makeStream(of: String.self)
        let watch = Task {
            try await AgentsDemoModes.watch(registry: registry) { continuation.yield($0) }
        }
        defer { watch.cancel() }
        var iterator = lines.makeAsyncIterator()

        let loadReport = await Self.nextLine(
            of: &iterator, startingWith: Self.reportPrefix(agentCount: FixtureLibrary.localAgentIDs.count))
        try library.write(Self.addedAgentText, at: Self.addedAgentPath)
        let changeReport = await Self.nextLine(
            of: &iterator, startingWith: Self.reportPrefix(agentCount: FixtureLibrary.localAgentIDs.count + 1))

        #expect(loadReport != nil)
        #expect(changeReport != nil)
        #expect(registry.catalog().definition(named: Self.addedAgentID) != nil)
    }

    // MARK: - --marketplace

    @Test("the marketplace mode lists each marketplace agent with its provenance")
    func marketplaceModeListsTheAgentsWithProvenance() async throws {
        let cache = try TemporaryLayer.makeEmpty()
        defer { try? cache.delete() }
        let store = AgentsDemoLibrary.marketplaceStore(libraryRoot: FixtureLibrary.root, cacheDirectory: cache.root)
        let registry = AgentRegistry(
            marketplaces: store, stack: AgentsDemoLibrary.stack(libraryRoot: FixtureLibrary.root))
        let (lines, continuation) = AsyncStream.makeStream(of: String.self)

        try await AgentsDemoModes.marketplace(registry: registry) { continuation.yield($0) }
        continuation.finish()
        let written: [String] = await lines.reduce(into: []) { $0.append($1) }

        #expect(Self.marketplaceLines.allSatisfy { written.contains($0) })
        #expect(written.count == FixtureLibrary.localAgentIDs.count + Self.marketplaceLines.count)
    }

    // MARK: - Helpers

    /// The text that opens the first report line of a catalog with
    /// `agentCount` agents.
    ///
    /// - Parameter agentCount: The number of agents in the catalog.
    /// - Returns: The prefix of the report line.
    private static func reportPrefix(agentCount: Int) -> String {
        "\(reportPrefix)\(agentCount) agents"
    }

    /// Reads lines until one starts with `prefix`.
    ///
    /// - Parameters:
    ///   - iterator: The iterator of the written lines.
    ///   - prefix: The text that the wanted line starts with.
    /// - Returns: The first line that starts with `prefix`, or `nil` when the
    ///   lines end first.
    private static func nextLine(
        of iterator: inout AsyncStream<String>.Iterator, startingWith prefix: String
    ) async -> String? {
        while let line = await iterator.next() {
            if line.hasPrefix(prefix) {
                return line
            }
        }
        return nil
    }

    /// The result of one run of the binary: its combined output and its exit
    /// code.
    private struct RunResult {
        /// The standard output and the standard error of the run.
        let output: String

        /// The exit code of the run.
        let exitCode: Int32
    }

    /// Runs the built binary to its end.
    ///
    /// - Parameter arguments: The arguments of the run.
    /// - Returns: The output and the exit code of the run.
    /// - Throws: An error when the binary is not found or does not start.
    private static func run(arguments: [String]) throws -> RunResult {
        let process = Process()
        process.executableURL = try binary()
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = try #require(String(bytes: data, encoding: .utf8))
        return RunResult(output: output, exitCode: process.terminationStatus)
    }

    /// Finds the built binary: next to the test bundle, or in `.build/debug/`.
    ///
    /// - Returns: The URL of the binary.
    /// - Throws: An error when no candidate is an executable file.
    private static func binary() throws -> URL {
        let bundleFolders = Bundle.allBundles.lazy
            .filter { $0.bundlePath.hasSuffix(".xctest") }
            .map { $0.bundleURL.deletingLastPathComponent() }
        let candidates = bundleFolders.map { $0.appendingPathComponent(binaryName) }
            + [PackageRoot.directory.appendingPathComponent(".build/debug/\(binaryName)")]
        return try #require(candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) })
    }
}
