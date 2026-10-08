import Foundation
import FoundationModelsAgents
import FoundationModelsRouter
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
        case .chat:
            try await withResolvedProfile {
                try await AgentsDemoModes.chat(profile: $0, registry: $1, workingDirectory: $2, input: $3, output: $4)
            }
        case .fanOut:
            try await withResolvedProfile {
                try await AgentsDemoModes.fanOut(profile: $0, registry: $1, workingDirectory: $2, input: $3, output: $4)
            }
        case .unknown(let flag):
            StandardStream.error.write(line: "agents-demo: unknown mode \(flag)")
            StandardStream.error.write(line: AgentsDemoUsage.text)
            exit(usageExitCode)
        }
    }

    /// Resolves the real profile of ``AgentsDemoProfile``, then runs a mode
    /// that needs a profile over the stack of `Examples/agent-library`.
    ///
    /// Only `--chat` and `--fan-out` call this function. The mode reads the
    /// lines of standard input, and ends at the end of the input. The router
    /// stays alive until the mode returns.
    ///
    /// - Parameter mode: The function of the mode.
    /// - Throws: The error of the resolve or of the mode.
    private static func withResolvedProfile(
        _ mode: (LanguageModelProfile, AgentRegistry, URL, AgentsDemoInput, @escaping AgentsDemoOutput)
            async throws -> Void
    ) async throws {
        let router = AgentsDemoProfile.makeRouter()
        let profile = try await AgentsDemoProfile.resolve(with: router)
        let registry = AgentRegistry(stack: AgentsDemoLibrary.stack(libraryRoot: AgentsDemoLibrary.root))
        try await mode(
            profile, registry, AgentsDemoLibrary.projectDirectory(libraryRoot: AgentsDemoLibrary.root),
            makeStandardInput(), standardOutput)
        withExtendedLifetime(router) {}
    }

    /// Makes a stream of the lines of standard input, as the input of a mode.
    ///
    /// A read task relays each line. The stream ends at the end of standard
    /// input. A read error ends the stream too, and the example writes the
    /// error to standard error.
    ///
    /// - Returns: The stream of the lines.
    private static func makeStandardInput() -> AgentsDemoInput {
        let (lines, continuation) = AgentsDemoInput.makeStream()
        let reader = Task {
            await relayStandardInput(to: continuation)
        }
        continuation.onTermination = { _ in reader.cancel() }
        return lines
    }

    /// Gives each line of standard input to `continuation`, then finishes
    /// the stream.
    ///
    /// - Parameter continuation: The continuation of the input of the mode.
    private static func relayStandardInput(to continuation: AgentsDemoInput.Continuation) async {
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                continuation.yield(line)
            }
        } catch {
            StandardStream.error.write(line: "agents-demo: standard input: \(error)")
        }
        continuation.finish()
    }
}
