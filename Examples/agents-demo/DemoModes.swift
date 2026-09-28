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

/// The lines that the user types, in order.
///
/// The binary gives the lines of standard input. A test gives a stream that
/// it controls, and ends the stream when it read the lines that it checks.
typealias AgentsDemoInput = AsyncStream<String>

/// The work of each mode of `agents-demo` (plan.md §12, §13).
///
/// Each function takes its registry and its output. The functions of
/// `--chat` and `--fan-out` also take a resolved profile and an input. Thus a
/// test calls each function with no process, and with a scripted profile.
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

    /// The instructions of the root session of the fan-out mode.
    static let fanOutInstructions = """
        You give work to agents. Use the agents tool to start two agents at the same time: \
        the agent "\(reviewerAgent)" with the task "\(reviewerPrompt)", and the agent \
        "\(testWriterAgent)" with the task "\(testWriterPrompt)". Then tell the user in one \
        short sentence what you did. When the final message of an agent comes, tell the user \
        its result in one short sentence.
        """

    /// The first prompt of the root session of the fan-out mode.
    static let fanOutPrompt = "Review the parse function in Sources/Parser.swift, and test it."

    /// The text that opens each answer of the root session.
    static let rootPrefix = "root: "

    /// The text that opens each line of an answer of the root session that
    /// failed.
    static let failedPrefix = "root failed: "

    /// The text of a cancelled run, and of an answer that a cancel stopped.
    static let cancelledText = "cancelled"

    /// The text that opens each `runSettled` line.
    static let settledPrefix = "settled: "

    /// The text that opens each `mailDeliveryPaused` line.
    static let pausedPrefix = "paused: "

    /// The line after each `mailDeliveryPaused` line: the held mail goes to
    /// the root session with the next message of the user.
    static let sendMessageHint = "Send a message to deliver the held mail."

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
    /// A root session on the `standard` slot gets the `agents` tool. The mode
    /// sends ``chatPrompt`` with `send(_:)`, then each line of `input`. The
    /// model starts ``leadAgent``, and `lead` starts ``reviewerAgent`` and
    /// ``testWriterAgent``. `start agent` is a background run: when `lead`
    /// ends, the Router pump gives its final message to the root session as
    /// mail, and starts the answer to it. The mode writes each answer from
    /// the session events, the answers that mail starts too, with no user
    /// input and no driver call. See ``lines(for:)``.
    ///
    /// The mode does not wait for the runs. When `input` ends, it cancels the
    /// runs of the root session, closes the session, and writes the run tree:
    /// each run with its state, and the children of each run indented.
    ///
    /// - Parameters:
    ///   - profile: The resolved profile of the runs and of the root session.
    ///   - registry: The registry of the agents. The mode loads it.
    ///   - workingDirectory: The working directory of each session.
    ///   - input: The lines of the user. The mode ends when they end.
    ///   - output: The receiver of each line.
    /// - Throws: The error of `load()`, or of the `agents` tool.
    static func chat(
        profile: LanguageModelProfile, registry: AgentRegistry, workingDirectory: URL,
        input: AgentsDemoInput, output: @escaping AgentsDemoOutput
    ) async throws {
        let runner = try await makeRunner(profile: profile, registry: registry, workingDirectory: workingDirectory)
        let conversation = Conversation(
            instructions: chatInstructions, firstPrompt: chatPrompt, profile: profile,
            workingDirectory: workingDirectory)
        let root = try await converse(conversation, runner: runner, input: input, output: output)
        await writeRuns(of: root, runner: runner, level: 0, output: output)
    }

    /// Runs the fan-out mode (plan.md §12, model-driven, two runs at once).
    ///
    /// The flow is the flow of ``chat(profile:registry:workingDirectory:input:output:)``
    /// with ``fanOutInstructions`` and ``fanOutPrompt``. The model starts
    /// ``reviewerAgent`` on the `flash` slot and ``testWriterAgent`` on the
    /// `standard` slot at the same time. The two slots have two generation
    /// queues, thus neither run waits for the other. The final message of
    /// each run comes to the root session as mail, and the mode writes the
    /// answer to it. When `input` ends, the mode writes one line for each
    /// run of the root session.
    ///
    /// - Parameters:
    ///   - profile: The resolved profile of the runs and of the root session.
    ///   - registry: The registry of the agents. The mode loads it.
    ///   - workingDirectory: The working directory of each session.
    ///   - input: The lines of the user. The mode ends when they end.
    ///   - output: The receiver of each line.
    /// - Throws: The error of `load()`, or of the `agents` tool.
    static func fanOut(
        profile: LanguageModelProfile, registry: AgentRegistry, workingDirectory: URL,
        input: AgentsDemoInput, output: @escaping AgentsDemoOutput
    ) async throws {
        let runner = try await makeRunner(profile: profile, registry: registry, workingDirectory: workingDirectory)
        let conversation = Conversation(
            instructions: fanOutInstructions, firstPrompt: fanOutPrompt, profile: profile,
            workingDirectory: workingDirectory)
        let root = try await converse(conversation, runner: runner, input: input, output: output)
        for run in await runner.runs(caller: root) {
            let model = run.agent.model ?? inheritedModel
            output(fanOutLine(agent: run.agent.id, model: model, text: status(of: run.state)))
        }
    }

    /// The lines of one event of the root session.
    ///
    /// `send(_:)` and mail give each reply whole in `answered`, and send no
    /// `textDelta`. Thus the answer line comes from `answered` only, and a
    /// `textDelta` gives no line.
    ///
    /// The switch names each case of `SessionEvent`, with no `default`. Thus a
    /// new case of the Router is a compile error here, and the demo decides
    /// its line.
    ///
    /// - Parameter event: The event.
    /// - Returns: A ``rootLine(_:)`` for `answered`, a ``failedPrefix`` line
    ///   for `answerFailed`, a ``settledPrefix`` line for `runSettled`, a
    ///   ``pausedPrefix`` line and ``sendMessageHint`` for
    ///   `mailDeliveryPaused`, and no line for each other event.
    static func lines(for event: SessionEvent) -> [String] {
        switch event {
        case .answered(let answer):
            [rootLine(answer.reply)]
        case .answerFailed(let failure):
            [failedPrefix + text(of: failure.reason)]
        case .runSettled(let terminal):
            [settledPrefix + terminal.detail]
        case .mailDeliveryPaused(let pause):
            [pausedPrefix + pause.description, sendMessageHint]
        case .textDelta, .textReset, .reasoningDelta, .toolCall, .toolStatus, .toolInvocation,
            .toolCallReport, .entryRecorded, .compaction, .discoveryPrimingFailed, .generationStalled,
            .submissionQueued, .submissionStarted, .submissionEnded, .repetitionStopped,
            .elicitationRequested, .generationCall:
            []
        }
    }

    /// The text of the reason of an answer that failed.
    ///
    /// - Parameter reason: The reason.
    /// - Returns: ``cancelledText``, or the text of the error.
    static func text(of reason: AnswerFailure.Reason) -> String {
        switch reason {
        case .cancelled:
            cancelledText
        case .error(let description):
            description
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
            cancelledText
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

    /// The root session of one conversation mode, and its first prompt.
    private struct Conversation {
        /// The instructions of the root session.
        let instructions: String

        /// The prompt that the mode sends before the first line of the input.
        let firstPrompt: String

        /// The resolved profile. The root session is on its `standard` slot.
        let profile: LanguageModelProfile

        /// The working directory of the root session.
        let workingDirectory: URL
    }

    /// Runs the root session of one conversation mode until `input` ends.
    ///
    /// The function subscribes to the session events before the first
    /// message, and one writer task writes the ``lines(for:)`` of each event.
    /// It sends the first prompt, then each line of `input`, with
    /// `send(_:)`. It calls no driver method: the Router pump delivers the
    /// mail of the runs and starts the answers to it. When `input` ends, the
    /// function cancels the runs of the session and waits for them, then
    /// closes the session. `close()` ends the event stream, thus the writer
    /// ends after the last event.
    ///
    /// - Parameters:
    ///   - conversation: The root session to make, and its first prompt.
    ///   - runner: The runner of the runs of the session.
    ///   - input: The lines of the user.
    ///   - output: The receiver of each line.
    /// - Returns: The id of the root session.
    /// - Throws: The error of `AgentsTool.make(context:)`.
    private static func converse(
        _ conversation: Conversation, runner: AgentRunner, input: AgentsDemoInput,
        output: @escaping AgentsDemoOutput
    ) async throws -> ULID {
        let agentsTool = try await AgentsTool.make(context: AgentsToolContext(runner: runner))
        let root = conversation.profile.standard.makeSession(
            instructions: conversation.instructions, workingDirectory: conversation.workingDirectory,
            tools: [agentsTool])
        let events = await root.streamSessionEvents()
        let writer = Task {
            await write(events, to: output)
        }
        _ = await root.send(conversation.firstPrompt)
        for await line in input {
            _ = await root.send(line)
        }
        await runner.cancelRuns(caller: root.id)
        await root.close()
        await writer.value
        return root.id
    }

    /// Writes the ``lines(for:)`` of each event of `events`, until the stream
    /// ends.
    ///
    /// - Parameters:
    ///   - events: The session events of the root session.
    ///   - output: The receiver of each line.
    private static func write(_ events: AsyncStream<SessionEvent>, to output: AgentsDemoOutput) async {
        for await event in events {
            for line in lines(for: event) {
                output(line)
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
}
