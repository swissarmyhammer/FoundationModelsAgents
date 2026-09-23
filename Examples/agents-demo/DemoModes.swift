import Foundation
import FoundationModelsAgents
import FoundationModelsRouter
import FoundationModelsSkills
import ULID

/// The receiver of each line that a mode writes.
///
/// The binary gives a closure that writes the line with `StandardStream`. A
/// test gives a closure that keeps the line.
typealias AgentsDemoOutput = @Sendable (String) -> Void

/// The work of each mode of `agents-demo` (plan.md §12, §13).
///
/// Each function takes its registry and its output. The functions of
/// `--chat` and `--fan-out` also take a resolved profile. Thus a test calls
/// each function with no process, and with a scripted profile.
enum AgentsDemoModes {
    /// The agent that the root session of the chat mode starts. It starts
    /// ``reviewerAgent`` and ``testWriterAgent``.
    static let leadAgent = "lead"

    /// The agent of the library on the `flash` slot.
    static let reviewerAgent = "code-reviewer"

    /// The agent of the library on the `standard` slot.
    static let testWriterAgent = "test-writer"

    /// The instructions of the root session of the chat mode.
    static let chatInstructions = """
        You give work to agents. Use the agents tool to start the agent "\(leadAgent)" with \
        the task of the user. Then tell the user in one short sentence what you did.
        """

    /// The first prompt of the root session of the chat mode.
    static let chatPrompt = "Review the parse function in Sources/Parser.swift, and write the tests that it needs."

    /// The prompt of the ``reviewerAgent`` run of the fan-out mode.
    static let reviewerPrompt = "Review the parse function in Sources/Parser.swift."

    /// The prompt of the ``testWriterAgent`` run of the fan-out mode.
    static let testWriterPrompt = "Write one unit test for the parse function in Sources/Parser.swift."

    /// The text that opens each answer of the root session.
    static let rootPrefix = "root: "

    /// The text that opens each `runSettled` line of the chat mode.
    static let settledPrefix = "settled: "

    /// The indent of each level of the run tree of the chat mode.
    static let levelIndent = "  "

    /// The model text of an agent with no `model` field.
    static let inheritedModel = "inherit"

    /// Loads the registry, then writes one `AgentReloadReport` for each
    /// catalog that `onReload` publishes, the catalog of the load too.
    ///
    /// The function takes `onReload` before `load()`, thus it gets each
    /// catalog. It returns when the task is cancelled, or when the stream
    /// ends.
    ///
    /// - Parameters:
    ///   - registry: The registry to watch. Make it with `watch: true` to get
    ///     a report for each change of a layer root.
    ///   - output: The receiver of each report line.
    /// - Throws: The error of the first `load()`.
    static func watch(registry: AgentRegistry, output: AgentsDemoOutput) async throws {
        let reloads = registry.onReload
        try await registry.load()
        for await catalog in reloads {
            let report = AgentReloadReport(catalog: catalog, marketplaceLayers: registry.marketplaceLayers)
            for line in report.lines {
                output(line)
            }
        }
    }

    /// Loads the registry, then writes one line for each agent: its id and
    /// its provenance.
    ///
    /// - Parameters:
    ///   - registry: The registry to list, for example a registry over a
    ///     marketplace store.
    ///   - output: The receiver of each line.
    /// - Throws: The error of `load()`.
    static func marketplace(registry: AgentRegistry, output: AgentsDemoOutput) async throws {
        try await registry.load()
        for definition in registry.catalog().definitions {
            output(provenanceLine(of: definition))
        }
    }

    /// The line of one agent: `<id>: marketplace <marketplace>` for an agent
    /// of a marketplace layer, else `<id>: local <layer source>`.
    ///
    /// - Parameter definition: The agent.
    /// - Returns: The line of the agent.
    static func provenanceLine(of definition: AgentDefinition) -> String {
        guard let marketplace = definition.marketplace else {
            return "\(definition.id): local \(definition.layer.source)"
        }
        return "\(definition.id): marketplace \(marketplace.displayText)"
    }

    /// Runs the chat mode (plan.md §12, model-driven).
    ///
    /// A root session on the `standard` slot gets the `agents` tool and
    /// ``chatPrompt``. The model starts ``leadAgent``, and `lead` starts
    /// ``reviewerAgent`` and ``testWriterAgent``. The mode writes the answer
    /// of the first turn. Then, for each run that the first turn started, it
    /// waits for the `runSettled` event, writes it, and calls
    /// `dispatchNextPrompt()` to give the final message to the model. Then
    /// it calls `cancelRuns(caller:)`, because `close()` does not know the
    /// runs of the session, and closes the session. Last, it writes the run
    /// tree: each run with its state, and the children of each run indented.
    ///
    /// - Parameters:
    ///   - profile: The resolved profile of the runs and of the root session.
    ///   - registry: The registry of the agents. The mode loads it.
    ///   - workingDirectory: The working directory of each session.
    ///   - output: The receiver of each line.
    /// - Throws: The error of `load()`, of the `agents` tool, or of a turn of
    ///   the root session.
    static func chat(
        profile: LanguageModelProfile, registry: AgentRegistry, workingDirectory: URL, output: AgentsDemoOutput
    ) async throws {
        let runner = try await makeRunner(profile: profile, registry: registry, workingDirectory: workingDirectory)
        let agentsTool = try await AgentsTool.make(context: AgentsToolContext(runner: runner))
        let root = profile.standard.makeSession(
            instructions: chatInstructions, workingDirectory: workingDirectory, tools: [agentsTool])
        let failure: (any Error)?
        do {
            try await converse(with: root, runner: runner, output: output)
            failure = nil
        } catch {
            failure = error
        }
        await runner.cancelRuns(caller: root.id)
        await root.close()
        await writeRuns(of: root.id, runner: runner, level: 0, output: output)
        if let failure {
            throw failure
        }
    }

    /// Runs the fan-out mode (plan.md §12, host-driven).
    ///
    /// The mode starts ``reviewerAgent`` on the `flash` slot and
    /// ``testWriterAgent`` on the `standard` slot with `async let`, thus the
    /// two runs work at the same time. The two slots have two generation
    /// gates, thus neither run waits for the other. The mode writes one line
    /// for each result.
    ///
    /// - Parameters:
    ///   - profile: The resolved profile of the runs.
    ///   - registry: The registry of the agents. The mode loads it.
    ///   - workingDirectory: The working directory of each run.
    ///   - output: The receiver of each line.
    /// - Throws: The error of `load()`, of a start, or of a run.
    static func fanOut(
        profile: LanguageModelProfile, registry: AgentRegistry, workingDirectory: URL, output: AgentsDemoOutput
    ) async throws {
        let runner = try await makeRunner(profile: profile, registry: registry, workingDirectory: workingDirectory)
        async let review = resultLine(of: reviewerAgent, prompt: reviewerPrompt, runner: runner)
        async let tests = resultLine(of: testWriterAgent, prompt: testWriterPrompt, runner: runner)
        for line in try await [review, tests] {
            output(line)
        }
    }

    /// The line of one answer of the root session.
    ///
    /// - Parameter text: The answer.
    /// - Returns: ``rootPrefix``, then the answer.
    static func rootLine(_ text: String) -> String {
        rootPrefix + text
    }

    /// The line of one run in the run tree of the chat mode.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent of the run.
    ///   - status: The text of the state of the run.
    ///   - level: The depth in the tree. A run of the root session is at 0.
    /// - Returns: One ``levelIndent`` for each level, then `<agent>: <status>`.
    static func runLine(agent: String, status: String, level: Int) -> String {
        String(repeating: levelIndent, count: level) + "\(agent): \(status)"
    }

    /// The text of the state of a run.
    ///
    /// - Parameter state: The state.
    /// - Returns: The final text of a finished run, or a word for the other
    ///   states.
    static func status(of state: AgentRunState) -> String {
        switch state {
        case .running:
            "running"
        case .finished(let text):
            text
        case .failed(let failure):
            "failed: \(failure)"
        case .cancelled:
            "cancelled"
        }
    }

    /// The line of one result of the fan-out mode.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent of the run.
    ///   - model: The `model` field of the agent, or ``inheritedModel``.
    ///   - text: The result of the run.
    /// - Returns: `<agent> on <model>: <text>`.
    static func fanOutLine(agent: String, model: String, text: String) -> String {
        "\(agent) on \(model): \(text)"
    }

    /// Loads the registry, and makes a runner over it with an environment of
    /// `profile`. The runs get no skills.
    ///
    /// - Parameters:
    ///   - profile: The resolved profile of the runs.
    ///   - registry: The registry of the agents.
    ///   - workingDirectory: The working directory of each run.
    /// - Returns: The runner.
    /// - Throws: The error of `load()`.
    private static func makeRunner(
        profile: LanguageModelProfile, registry: AgentRegistry, workingDirectory: URL
    ) async throws -> AgentRunner {
        try await registry.load()
        let environment = AgentEnvironment(
            profile: profile, skills: SkillsRegistry(roots: []), workingDirectory: workingDirectory)
        return AgentRunner(registry: registry, environment: environment)
    }

    /// Runs the turns of the root session of the chat mode.
    ///
    /// The function subscribes to the session events before the first turn,
    /// thus it gets each `runSettled` event.
    ///
    /// - Parameters:
    ///   - root: The root session with the `agents` tool.
    ///   - runner: The runner of the runs of the session.
    ///   - output: The receiver of each line.
    /// - Throws: The error of a turn.
    private static func converse(
        with root: any RoutedSession, runner: AgentRunner, output: AgentsDemoOutput
    ) async throws {
        let sessionEvents = await root.streamSessionEvents()
        output(rootLine(try await root.streamEvents(to: chatPrompt).reduce("", text(_:after:))))
        let started = await runner.runs(caller: root.id)
        try await deliverSettledRuns(count: started.count, from: sessionEvents, to: root, output: output)
    }

    /// Writes each `runSettled` event, and runs one delivery turn after
    /// each, until `count` runs have settled.
    ///
    /// - Parameters:
    ///   - count: The count of runs to wait for.
    ///   - events: The session events of `root`.
    ///   - root: The root session.
    ///   - output: The receiver of each line.
    /// - Throws: The error of a delivery turn.
    private static func deliverSettledRuns(
        count: Int, from events: AsyncStream<SessionEvent>, to root: any RoutedSession, output: AgentsDemoOutput
    ) async throws {
        guard count > 0 else { return }
        var remaining = count
        for await case .runSettled(let terminal) in events {
            output(settledPrefix + terminal.detail)
            if let answer = try await root.dispatchNextPrompt() {
                output(rootLine(answer))
            }
            remaining -= 1
            if remaining == 0 {
                return
            }
        }
    }

    /// Writes the line of each run of `caller`, and after each run the lines
    /// of its children one level deeper.
    ///
    /// - Parameters:
    ///   - caller: The session that started the runs.
    ///   - runner: The runner of the runs.
    ///   - level: The depth of the runs of `caller` in the tree.
    ///   - output: The receiver of each line.
    private static func writeRuns(of caller: ULID, runner: AgentRunner, level: Int, output: AgentsDemoOutput) async {
        for run in await runner.runs(caller: caller) {
            output(runLine(agent: run.agent.id, status: status(of: run.state), level: level))
            await writeRuns(of: run.id, runner: runner, level: level + 1, output: output)
        }
    }

    /// Gives the text of a turn after one more event of the turn.
    ///
    /// - Parameters:
    ///   - text: The text before `event`.
    ///   - event: The next event of the turn.
    /// - Returns: The text with the fragment of a `textDelta`, an empty text
    ///   after a `textReset`, or `text` for each other event.
    private static func text(_ text: String, after event: SessionEvent) -> String {
        if case .textDelta(let fragment) = event {
            return text + fragment
        }
        if case .textReset = event {
            return ""
        }
        return text
    }

    /// Starts one host-driven run and gives its line.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent.
    ///   - prompt: The prompt of the run.
    ///   - runner: The runner.
    /// - Returns: The line of the result of the run.
    /// - Throws: The error of the start or of the run.
    private static func resultLine(of agent: String, prompt: String, runner: AgentRunner) async throws -> String {
        let run = try await runner.start(agent, prompt: prompt)
        return fanOutLine(agent: agent, model: run.agent.model ?? inheritedModel, text: try await run.result())
    }
}
