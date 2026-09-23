import Foundation
import FoundationModelsExtras

/// The conformance of `AgentRunner` to the slash-command channel of Extras
/// (plan.md §9.4).
///
/// Each user-invocable agent gives one command. The name of the command is
/// the id of the agent. When the user runs `/name text`, the `.action` body
/// starts a host-driven run of the agent with `text` as the prompt, unchanged.
/// The body waits for the run and gives its final text. The body is never a
/// prompt for the host session: `/code-reviewer check the diff` gives the task
/// to the agent. The prompt is `$ARGUMENTS` of the body of the agent.
///
/// Skills and agents are separate things. This conformance gives commands for
/// agents only. `SkillsRegistry` gives the commands of the skills.
extension AgentRunner: SlashCommandProviding {
    /// The argument hint of each command: the text after the name is the
    /// task of the agent.
    static let taskArgumentHint = "<task>"

    /// One command for each user-invocable agent of the current catalog of
    /// the registry, in id order.
    ///
    /// The catalog is empty before `registry.load()`, thus there is no
    /// command before the load.
    ///
    /// - Parameter workingDirectory: The working directory of the session.
    ///   Not used: each run uses ``AgentEnvironment/workingDirectory``.
    /// - Returns: One command for each user-invocable agent.
    public nonisolated func commands(workingDirectory: URL) async -> [SlashCommand] {
        slashCommands(for: registry.catalog())
    }

    /// The full command list after each new catalog of the registry
    /// (plan.md §9.4).
    ///
    /// The stream follows `AgentRegistry.onReload`. Each access makes a
    /// subscription of its own, thus two readers each get each list. The
    /// stream gets the list of each catalog that a build swaps in after the
    /// access. It finishes when the registry is released or when the reader
    /// cancels it.
    ///
    /// The follow task keeps a weak reference to the runner. Thus the stream
    /// does not keep the runner alive, and it finishes when the runner is
    /// released and the next catalog arrives.
    public nonisolated var commandUpdates: AsyncStream<[SlashCommand]>? {
        let reloads = registry.onReload
        let (stream, continuation) = AsyncStream<[SlashCommand]>.makeStream()
        let commandsOfCatalog: @Sendable (AgentCatalog) -> [SlashCommand]? = { [weak self] catalog in
            self?.slashCommands(for: catalog)
        }
        let follow = Task {
            await Self.relay(reloads, commands: commandsOfCatalog, to: continuation)
        }
        continuation.onTermination = { _ in follow.cancel() }
        return stream
    }

    /// Gives the command list of each catalog of `reloads` to
    /// `continuation`, then finishes the stream.
    ///
    /// - Parameters:
    ///   - reloads: An `onReload` stream of the registry.
    ///   - commands: Gives the command list of one catalog, or `nil` when the
    ///     runner was released.
    ///   - continuation: The continuation of the `commandUpdates` stream.
    private static func relay(
        _ reloads: AsyncStream<AgentCatalog>,
        commands: @Sendable (AgentCatalog) -> [SlashCommand]?,
        to continuation: AsyncStream<[SlashCommand]>.Continuation
    ) async {
        for await catalog in reloads {
            guard let list = commands(catalog) else { break }
            continuation.yield(list)
        }
        continuation.finish()
    }

    /// Starts a host-driven run of the agent `name`, waits for it, and gives
    /// its final text.
    ///
    /// A cancel of the task that waits cancels the run.
    ///
    /// - Parameters:
    ///   - name: The id of the agent.
    ///   - prompt: The prompt of the run, unchanged.
    /// - Returns: The final text of the run.
    /// - Throws: ``AgentRunnerError/unknownAgent(name:available:)`` when the
    ///   catalog has no such agent, the ``AgentRunFailure`` of a failed run,
    ///   or `CancellationError` for a cancelled run.
    private nonisolated func finalText(ofAgent name: String, prompt: String) async throws -> String {
        let run = try await start(name, prompt: prompt)
        return try await withTaskCancellationHandler {
            try await run.result()
        } onCancel: {
            run.cancel()
        }
    }

    /// Gives one command for each user-invocable agent of `catalog`.
    ///
    /// - Parameter catalog: The catalog.
    /// - Returns: The commands, in id order.
    private nonisolated func slashCommands(for catalog: AgentCatalog) -> [SlashCommand] {
        catalog.userInvocable.map(slashCommand(for:))
    }

    /// Makes the command of one agent.
    ///
    /// - Parameter definition: The agent.
    /// - Returns: The command: `name` is the id of the agent, `description`
    ///   is its description (empty when absent), `argumentHint` is
    ///   ``taskArgumentHint``, and the `.action` body starts a run.
    private nonisolated func slashCommand(for definition: AgentDefinition) -> SlashCommand {
        let name = definition.id
        return SlashCommand(
            name: name,
            description: definition.description ?? "",
            argumentHint: Self.taskArgumentHint,
            body: .action { [self] invocation in
                finalTextStream(ofAgent: name, prompt: invocation.arguments)
            })
    }

    /// Gives a stream with the final text of one host-driven run.
    ///
    /// A cancel of the stream cancels the run.
    ///
    /// - Parameters:
    ///   - name: The id of the agent.
    ///   - prompt: The prompt of the run, unchanged.
    /// - Returns: A stream that gives the final text one time, then
    ///   finishes, or finishes with the error of the run.
    private nonisolated func finalTextStream(ofAgent name: String, prompt: String)
        -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let delivery = Task {
            await deliverFinalText(ofAgent: name, prompt: prompt, to: continuation)
        }
        continuation.onTermination = { _ in delivery.cancel() }
        return stream
    }

    /// Runs the agent, then gives its final text or its error to
    /// `continuation`, and finishes the stream.
    ///
    /// - Parameters:
    ///   - name: The id of the agent.
    ///   - prompt: The prompt of the run, unchanged.
    ///   - continuation: The continuation of the stream of the command.
    private nonisolated func deliverFinalText(
        ofAgent name: String, prompt: String, to continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        do {
            continuation.yield(try await finalText(ofAgent: name, prompt: prompt))
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
