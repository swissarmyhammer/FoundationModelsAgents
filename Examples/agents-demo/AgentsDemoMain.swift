import Foundation
import FoundationModelsAgents
import FoundationModelsSkills

/// The entry point of `agents-demo`, the example of plan.md §13.
///
/// The first argument selects the mode. With no mode, the example writes the
/// usage to standard output and exits 0. The work of each mode is in
/// `AgentsDemoModes`, thus a test calls it with no process.
///
/// The entry point is a `@main` type and not the top-level code of a
/// `main.swift` file. The test target imports this module, and periphery
/// reads no reference from top-level code in such a module.
@main
enum AgentsDemoMain {
    /// The exit code of a run with an unknown mode (`EX_USAGE`).
    static let usageExitCode: Int32 = 64

    /// The exit code of a mode that failed.
    static let failureExitCode: Int32 = 1

    /// Writes one line to standard output.
    static let standardOutput: AgentsDemoOutput = { StandardStream.output.write(line: $0) }

    /// Parses the mode from the arguments of the process, and runs it.
    static func main() async {
        do {
            try await run(mode: AgentsDemoMode(arguments: Array(CommandLine.arguments.dropFirst())))
        } catch {
            StandardStream.error.write(line: "agents-demo: \(error)")
            exit(failureExitCode)
        }
    }

    /// Runs one mode over the stack of `Examples/agent-library`.
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
