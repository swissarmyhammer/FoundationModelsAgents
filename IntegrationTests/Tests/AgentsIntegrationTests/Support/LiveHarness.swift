import Foundation
import FoundationModels
import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

/// The parent suite of each live suite of this package.
///
/// `.serialized` applies to each nested suite, thus one live test at a time
/// uses the models. The Router holds the generation gate of a model for the
/// whole turn, also while a tool call waits. Two live tests at the same time
/// can then block each other: a tool that waits in one test keeps a slot
/// busy that a run of the other test needs.
@Suite("Live", .serialized)
enum LiveSuites {}

/// The parts of one live test: a local layer of agent files, its registry,
/// and a runner over the live profile.
///
/// ``withHarness(agents:tools:watch:_:)`` makes the parts, gives them to the
/// test, and then stops the runner and removes the folders, also when the
/// test throws.
struct LiveHarness {
    /// The name of the `agents` tool in a session.
    static let agentsToolName = "agents"

    /// The op of `start agent`.
    static let startOperation = "start agent"

    /// The op of `check agent`.
    static let checkOperation = "check agent"

    /// The op of `cancel agent`.
    static let cancelOperation = "cancel agent"

    /// The instructions of a root session.
    static let rootInstructions = """
        You are a test driver. Do exactly what each prompt tells you to do. When a prompt \
        gives you a tool call, make exactly that tool call, also when you think that you know \
        its answer. Keep each answer to one short sentence.
        """

    /// The resolved live profile.
    let live: LiveProfile

    /// The root of the local layer. The agent files are in its `agents`
    /// folder.
    let layerRoot: URL

    /// The loaded registry over the local layer.
    let registry: AgentRegistry

    /// The runner over the registry and the live profile.
    let runner: AgentRunner

    /// The working directory of each run and of each root session.
    let workingDirectory: URL

    /// Makes the parts of one live test, runs `body`, then stops the runner
    /// and removes the folders.
    ///
    /// - Parameters:
    ///   - agents: The text of each agent file, by its path relative to the
    ///     layer root.
    ///   - tools: The tools that an agent can name in its `tools` field.
    ///   - watch: `true` to make the registry watch the layer root.
    ///   - body: The test.
    /// - Returns: The value of `body`.
    /// - Throws: The error of the setup, of the load, or of `body`.
    static func withHarness<Value>(
        agents: [String: String], tools: [any Tool] = [], watch: Bool = false,
        _ body: (LiveHarness) async throws -> Value
    ) async throws -> Value {
        let layerRoot = try LiveSourceTree.writeTemporaryFolder(holding: agents)
        defer { try? FileManager.default.removeItem(at: layerRoot) }
        let workingDirectory = try LiveSourceTree.makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let registry = AgentRegistry(
            stack: DotfolderStack(layers: [.init(source: .project, root: layerRoot)]), watch: watch)
        try await registry.load()
        let live = try await LiveProfile.shared.value
        let runner = live.makeRunner(
            registry: registry, workingDirectory: workingDirectory, tools: .holding(tools))
        let harness = LiveHarness(
            live: live, layerRoot: layerRoot, registry: registry, runner: runner, workingDirectory: workingDirectory)
        let outcome: Result<Value, any Error>
        do {
            outcome = .success(try await body(harness))
        } catch {
            outcome = .failure(error)
        }
        await runner.stop()
        return try outcome.get()
    }

    /// Gives the text that tells a model to make one call of the `agents`
    /// tool with fixed arguments.
    ///
    /// A small model follows an exact JSON object better than a free
    /// request.
    ///
    /// - Parameter arguments: The arguments of the call, for example `op`,
    ///   `name`, and `prompt`.
    /// - Returns: The instruction.
    /// - Throws: The error of the JSON encoder, or the error of `#require`
    ///   when the JSON is not UTF-8 text.
    static func agentsCallText(_ arguments: [String: String]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try #require(String(bytes: try encoder.encode(arguments), encoding: .utf8))
        return "Call the tool \"\(agentsToolName)\" one time with these arguments: \(json). "
            + "You must make this call, also when you think that you know its answer."
    }

    /// Gives the one run of `agent` in `runs`.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent.
    ///   - runs: The runs of one caller.
    /// - Returns: The first run of the agent.
    /// - Throws: The error of `#require` when no run of `runs` is a run of
    ///   `agent`.
    static func run(of agent: String, in runs: [AgentRun]) throws -> AgentRun {
        try #require(runs.first { $0.agent.id == agent }, "The runs were: \(runs.map(\.agent.id))")
    }

    /// Makes an `agents` tool over the runner, for a root session or for
    /// host calls.
    ///
    /// - Returns: The tool.
    /// - Throws: The error of `AgentsTool.make(context:)`.
    func makeAgentsTool() async throws -> AgentsTool {
        try await AgentsTool.make(context: AgentsToolContext(runner: runner))
    }

    /// Makes a root session on the `standard` slot with ``rootInstructions``
    /// and `tools`.
    ///
    /// - Parameter tools: The tools of the session.
    /// - Returns: The session. The caller closes it.
    func makeRootSession(tools: [any Tool]) -> any RoutedSession {
        live.profile.standard.makeSession(
            instructions: Self.rootInstructions, workingDirectory: workingDirectory, tools: tools)
    }

    /// Calls `tool` as the host, outside of a Router session. The caller of
    /// each run that the call starts is `nil`.
    ///
    /// - Parameters:
    ///   - tool: The `agents` tool.
    ///   - operation: The op, for example ``startOperation``.
    ///   - fields: The other arguments.
    /// - Returns: The plain-text answer of the tool.
    /// - Throws: The error of the tool.
    func call(_ tool: AgentsTool, _ operation: String, _ fields: [String: String]) async throws -> String {
        let properties = fields.merging(["op": operation]) { _, operation in operation }
            .lazy.map { field -> (String, any ConvertibleToGeneratedContent) in (field.key, field.value) }
        return try await tool.call(
            arguments: GeneratedContent(properties: Array(properties), uniquingKeysWith: { _, last in last }))
    }
}
