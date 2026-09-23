// The entry point of `agents-demo`, the example of plan.md §13.
//
// The first argument selects the mode. With no mode, the example writes the
// usage to standard output and exits 0. The work of each mode is in
// `AgentsDemoModes`, thus a test calls it with no process.

import Foundation
import FoundationModelsAgents
import FoundationModelsSkills

/// Runs `agents-demo` and ends the process with its exit code.
enum AgentsDemoMain {
    /// The exit code of a run with an unknown mode (`EX_USAGE`).
    static let usageExitCode: Int32 = 64

    /// The exit code of a mode that failed.
    static let failureExitCode: Int32 = 1

    /// Writes one line to standard output.
    static let standardOutput: AgentsDemoOutput = { StandardStream.output.write(line: $0) }

    /// Runs the mode of `arguments`.
    ///
    /// - Parameter arguments: The arguments, with no executable name.
    static func run(arguments: [String]) async {
        do {
            try await run(mode: AgentsDemoMode(arguments: arguments))
        } catch {
            StandardStream.error.write(line: "agents-demo: \(error)")
            exit(failureExitCode)
        }
    }

    /// Runs one mode.
    ///
    /// - Parameter mode: The mode to run.
    /// - Throws: The error of the mode.
    private static func run(mode: AgentsDemoMode) async throws {
        switch mode {
        case .usage:
            StandardStream.output.write(line: AgentsDemoUsage.text)
        case .watch:
            let registry = AgentRegistry(
                stack: AgentsDemoLibrary.stack(libraryRoot: AgentsDemoLibrary.root), watch: true)
            try await AgentsDemoModes.watch(registry: registry, output: standardOutput)
        case .marketplace:
            let store = AgentsDemoLibrary.marketplaceStore(
                libraryRoot: AgentsDemoLibrary.root, cacheDirectory: AgentsDemoLibrary.cacheDirectory)
            let registry = AgentRegistry(
                marketplaces: store, stack: AgentsDemoLibrary.stack(libraryRoot: AgentsDemoLibrary.root))
            try await AgentsDemoModes.marketplace(registry: registry, output: standardOutput)
        case .unknown(let flag):
            StandardStream.error.write(line: "agents-demo: unknown mode \(flag)")
            StandardStream.error.write(line: AgentsDemoUsage.text)
            exit(usageExitCode)
        }
    }
}

await AgentsDemoMain.run(arguments: Array(CommandLine.arguments.dropFirst()))
