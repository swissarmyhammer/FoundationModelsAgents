import Foundation
import FoundationModelsAgents
import FoundationModelsRouter
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
        #expect(AgentsDemoMode(arguments: [AgentsDemoMode.chatFlag]) == .chat)
        #expect(AgentsDemoMode(arguments: [AgentsDemoMode.fanOutFlag]) == .fanOut)
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
            of: &iterator, startingWith: Self.reportPrefix(for: FixtureLibrary.localAgentIDs.count))
        try library.write(Self.addedAgentText, at: Self.addedAgentPath)
        let changeReport = await Self.nextLine(
            of: &iterator, startingWith: Self.reportPrefix(for: FixtureLibrary.localAgentIDs.count + 1))

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
    private static func reportPrefix(for agentCount: Int) -> String {
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

/// The contract of the two modes of `agents-demo` that need a resolved
/// profile: `--chat` and `--fan-out` (plan.md §12, §13).
///
/// Each case gives a scripted profile to the function of the mode. The root
/// session and the `lead` run are on the `standard` slot. The one gated run
/// is code-reviewer on the `flash` slot, thus the gated turn does not hold
/// the generation gate of another turn.
@Suite("agents-demo with a profile")
struct AgentsDemoProfileModeTests {
    /// The prompt that the root session gives to the `lead` run.
    private static let leadKey = "demo-lead-key: divide the task"

    /// The prompt that the lead gives to the code-reviewer child.
    private static let reviewerKey = "demo-reviewer-key: review the parser"

    /// The prompt that the lead gives to the test-writer child.
    private static let testWriterKey = "demo-test-writer-key: test the parser"

    /// The prompt of the code-reviewer run that the root session starts in
    /// its delivery turn. The run waits on a gate that never opens.
    private static let lateReviewerKey = "demo-late-key: review the parser again"

    /// The final text of the code-reviewer runs.
    private static let reviewerText = "The parser is correct."

    /// The final text of the test-writer runs.
    private static let testWriterText = "The tests of the parser pass."

    /// The text that the gated run gives when its gate opens.
    private static let lateReviewerText = "The parser is still correct."

    /// The answer of the first turn of the root session.
    private static let rootText = "I started the lead agent."

    /// The answer of the delivery turn of the root session.
    private static let deliveredText = "The lead agent finished."

    /// The file that each Router session writes in its recording directory.
    private static let sidecarName = "session.json"

    @Test("the chat mode writes the result of each child and the final text of lead", .timeLimit(.minutes(1)))
    func chatModeWritesEachResult() async throws {
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: AgentsDemoModes.chatInstructions,
                steps: [
                    NestedRunTests.startStep(AgentsDemoModes.leadAgent, prompt: Self.leadKey),
                    .finalText(Self.rootText),
                    .finalText(Self.deliveredText)
                ]),
            NestedRunTests.parentPlay(
                Self.leadKey,
                children: [
                    (AgentsDemoModes.reviewerAgent, Self.reviewerKey),
                    (AgentsDemoModes.testWriterAgent, Self.testWriterKey)
                ]),
            ScriptedAgentPlay(key: Self.reviewerKey, steps: [.finalText(Self.reviewerText)]),
            ScriptedAgentPlay(key: Self.testWriterKey, steps: [.finalText(Self.testWriterText)])
        ])

        let written = try await Self.chatLines(script: script)
        let leadPrefix = AgentsDemoModes.runLine(agent: AgentsDemoModes.leadAgent, status: "", level: 0)
        let leadLine = try #require(written.first { $0.hasPrefix(leadPrefix) })

        #expect(written.contains(AgentsDemoModes.rootLine(Self.rootText)))
        #expect(written.contains(AgentsDemoModes.rootLine(Self.deliveredText)))
        #expect(written.contains { $0.hasPrefix(AgentsDemoModes.settledPrefix) })
        #expect(written.contains(
            AgentsDemoModes.runLine(agent: AgentsDemoModes.reviewerAgent, status: Self.reviewerText, level: 1)))
        #expect(written.contains(
            AgentsDemoModes.runLine(agent: AgentsDemoModes.testWriterAgent, status: Self.testWriterText, level: 1)))
        #expect(leadLine.contains(Self.reviewerText))
        #expect(leadLine.contains(Self.testWriterText))
    }

    @Test("the chat mode cancels the open runs of the root session before it closes the session",
        .timeLimit(.minutes(1)))
    func chatModeCancelsOpenRunsBeforeClose() async throws {
        let gate = ScriptedGate()
        defer { gate.open() }
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: AgentsDemoModes.chatInstructions,
                steps: [
                    NestedRunTests.startStep(AgentsDemoModes.leadAgent, prompt: Self.leadKey),
                    .finalText(Self.rootText),
                    NestedRunTests.startStep(AgentsDemoModes.reviewerAgent, prompt: Self.lateReviewerKey),
                    .finalText(Self.deliveredText)
                ]),
            NestedRunTests.parentPlay(Self.leadKey, children: [(AgentsDemoModes.reviewerAgent, Self.reviewerKey)]),
            ScriptedAgentPlay(key: Self.reviewerKey, steps: [.finalText(Self.reviewerText)]),
            ScriptedAgentPlay(key: Self.lateReviewerKey, steps: [.wait(gate), .finalText(Self.lateReviewerText)])
        ])

        let written = try await Self.chatLines(script: script)
        let cancelledLine = AgentsDemoModes.runLine(
            agent: AgentsDemoModes.reviewerAgent, status: AgentsDemoModes.status(of: .cancelled), level: 0)

        #expect(written.contains(cancelledLine))
        #expect(written.contains(AgentsDemoModes.rootLine(Self.deliveredText)))
        #expect(!written.contains { $0.contains(Self.lateReviewerText) })
    }

    @Test("the fan-out mode writes two results, one from each generation slot", .timeLimit(.minutes(1)))
    func fanOutModeWritesOneResultFromEachSlot() async throws {
        let recordings = try TemporaryLayer.makeEmpty()
        defer { try? recordings.delete() }
        let workingDirectory = try TemporaryLayer.makeEmpty()
        defer { try? workingDirectory.delete() }
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(key: AgentsDemoModes.reviewerPrompt, steps: [.finalText(Self.reviewerText)]),
            ScriptedAgentPlay(key: AgentsDemoModes.testWriterPrompt, steps: [.finalText(Self.testWriterText)])
        ])
        let (router, profile) = try await ScriptedProfile.make(script: script, recordingsDir: recordings.root)

        let written = try await Self.lines { output in
            try await AgentsDemoModes.fanOut(
                profile: profile, registry: AgentRegistry(stack: FixtureLibrary.stack()),
                workingDirectory: workingDirectory.root, output: output)
        }
        let slots = try Self.recordedSlots(in: recordings.root)
        withExtendedLifetime(router) {}

        #expect(written.sorted() == [
            AgentsDemoModes.fanOutLine(
                agent: AgentsDemoModes.reviewerAgent, model: ModelSlot.flash.rawValue, text: Self.reviewerText),
            AgentsDemoModes.fanOutLine(
                agent: AgentsDemoModes.testWriterAgent, model: ModelSlot.standard.rawValue, text: Self.testWriterText)
        ].sorted())
        #expect(slots.map(\.rawValue).sorted() == [ModelSlot.flash, ModelSlot.standard].map(\.rawValue).sorted())
    }

    // MARK: - Helpers

    /// Runs the chat mode over the fixture library with a scripted profile
    /// that plays `script`.
    ///
    /// - Parameter script: The script of each generation slot.
    /// - Returns: The lines that the mode wrote, in order.
    /// - Throws: The error of the profile, of the file system, or of the mode.
    private static func chatLines(script: ScriptedAgentScript) async throws -> [String] {
        let recordings = try TemporaryLayer.makeEmpty()
        defer { try? recordings.delete() }
        let workingDirectory = try TemporaryLayer.makeEmpty()
        defer { try? workingDirectory.delete() }
        let (router, profile) = try await ScriptedProfile.make(script: script, recordingsDir: recordings.root)
        let written = try await lines { output in
            try await AgentsDemoModes.chat(
                profile: profile, registry: AgentRegistry(stack: FixtureLibrary.stack()),
                workingDirectory: workingDirectory.root, output: output)
        }
        withExtendedLifetime(router) {}
        return written
    }

    /// Runs `body` with an output that keeps each line.
    ///
    /// - Parameter body: The work that writes the lines.
    /// - Returns: The lines that `body` wrote, in order.
    /// - Throws: The error of `body`.
    private static func lines(
        of body: @escaping (AgentsDemoOutput) async throws -> Void
    ) async throws -> [String] {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        try await body { continuation.yield($0) }
        continuation.finish()
        return await stream.reduce(into: []) { $0.append($1) }
    }

    /// Reads the slot of each Router session that recorded under `directory`.
    ///
    /// - Parameter directory: The recordings root of the router.
    /// - Returns: The slot of each `session.json` under the folder.
    /// - Throws: The error of `#require`, of the read, or of the decode.
    private static func recordedSlots(in directory: URL) throws -> [ModelSlot] {
        let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        return try files.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == sidecarName }
            .map { try RecordedSidecar.read(in: $0.deletingLastPathComponent()).slot }
    }
}
