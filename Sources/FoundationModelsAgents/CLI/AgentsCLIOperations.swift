import FoundationModels
import FoundationModelsSkills
import Operations

/// The reason that a command of `AgentsCLI` did not work.
///
/// A command throws this error in place of a corrective answer.
/// `OperationTool` gives the error to `OperationCLIDriver` as
/// `OperationError.executionFailed(cause:)`, and the driver gives its text
/// with a non-zero exit code. Thus a shell sees that the command did not work.
struct AgentsCLIFailure: Error, Equatable, CustomStringConvertible {
    /// The text of the reason: a corrective of the `agents` tool, or the
    /// report of a run that did not finish.
    let description: String
}

extension CorrectiveOutcome where Success == String {
    /// Gives the text of a success, or throws the text of a corrective.
    ///
    /// - Returns: The text of `.success`.
    /// - Throws: ``AgentsCLIFailure`` with the text of `.corrective`.
    func successText() throws(AgentsCLIFailure) -> String {
        switch self {
        case .success(let text):
            return text
        case .corrective(let text):
            throw AgentsCLIFailure(description: text)
        }
    }
}

/// Lists the agents that a command can start (`agents agent list`).
@Generable
@Operation(verb: "list", noun: "agent", description: "List each agent that you can start, with its description.")
struct ListAgentCommand {
    /// Text that the name or the description of an agent must hold.
    @Guide(description: "Case-insensitive text to find in the name or the description of an agent.")
    var filter: String?
}

extension ListAgentCommand {
    /// Gives one `- name: description` line for each model-visible agent
    /// that matches `filter`.
    ///
    /// - Parameter context: The shared context of the commands.
    /// - Returns: The lines, or "No agents are available." when no agent
    ///   matches.
    func execute(in context: AgentsToolContext) async throws -> String {
        let matches = context.startableAgents(matching: filter)
        guard !matches.isEmpty else {
            return AgentsToolText.noAgents
        }
        return AgentsToolDescription.lines(for: matches.map(AgentsToolDescription.Entry.init))
    }
}

/// Starts an agent on a task and waits for the run
/// (`agents agent start`).
@Generable
@Operation(
    verb: "start", noun: "agent",
    description: "Start an agent on a task, wait for the run, and give its final text.")
struct StartAgentCommand {
    /// The name of the agent to start.
    @Guide(description: "The name of the agent to start.")
    var name: String

    /// The full task for the agent.
    @Guide(description: "The full task. The agent sees only this text.")
    var prompt: String
}

extension StartAgentCommand {
    /// Starts a host-driven run of the agent `name` with `prompt`, waits for
    /// the run, and gives its final text.
    ///
    /// The run has no `ToolContext`, thus it posts nothing. It has depth one
    /// and runs on ``AgentEnvironment/defaultSlot`` for `model: inherit`.
    ///
    /// - Parameter context: The shared context of the commands.
    /// - Returns: The final text of the run.
    /// - Throws: ``AgentsCLIFailure`` with the corrective of the `agents` tool
    ///   for a blank prompt or for a name that is not a model-visible agent,
    ///   and with the report of the run when the run fails or is cancelled.
    func execute(in context: AgentsToolContext) async throws -> String {
        guard AgentDefinitionRules.holdsText(prompt) else {
            throw AgentsCLIFailure(description: AgentsToolText.blankPrompt)
        }
        let startable = context.startableAgents().map(\.id)
        guard startable.contains(name) else {
            throw AgentsCLIFailure(description: AgentsToolText.unknownAgent(name, available: startable))
        }
        let run = try await start(on: context.runner)
        do {
            return try await run.result()
        } catch {
            throw AgentsCLIFailure(description: run.report)
        }
    }

    /// Starts the host-driven run of the agent `name`.
    ///
    /// - Parameter runner: The runner of the commands.
    /// - Returns: The run.
    /// - Throws: ``AgentsCLIFailure`` with the unknown-agent corrective when
    ///   a reload removed the agent after the check of `execute(in:)`.
    private func start(on runner: AgentRunner) async throws(AgentsCLIFailure) -> AgentRun {
        do {
            return try await runner.start(name, prompt: prompt)
        } catch {
            switch error {
            case .unknownAgent(let name, let available):
                throw AgentsCLIFailure(description: AgentsToolText.unknownAgent(name, available: available))
            }
        }
    }
}

/// Gives the state of a run (`agents agent check`).
@Generable
@Operation(verb: "check", noun: "agent", description: "Get the state of a run. The call never waits.")
struct CheckAgentCommand {
    /// The id of the run, or `nil` for each host-driven run.
    @Guide(description: "The id of the run. With no id, you get each run that you started.")
    var id: String?
}

extension CheckAgentCommand {
    /// Gives the answer of the `check agent` operation of the tool.
    ///
    /// - Parameter context: The shared context of the commands.
    /// - Returns: The report of the run, or of each host-driven run when
    ///   there is no `id`.
    /// - Throws: ``AgentsCLIFailure`` with the corrective for an id that no
    ///   host-driven run has.
    func execute(in context: AgentsToolContext) async throws -> String {
        try await CheckAgent(id: id).execute(in: context).successText()
    }
}

/// Cancels a run (`agents agent cancel`).
@Generable
@Operation(verb: "cancel", noun: "agent", description: "Cancel a run and the runs that it started.")
struct CancelAgentCommand {
    /// The id of the run to cancel.
    @Guide(description: "The id of the run to cancel.")
    var id: String
}

extension CancelAgentCommand {
    /// Gives the answer of the `cancel agent` operation of the tool.
    ///
    /// - Parameter context: The shared context of the commands.
    /// - Returns: The text of the `CancelOutcome`.
    /// - Throws: ``AgentsCLIFailure`` with the corrective for an id that no
    ///   host-driven run has.
    func execute(in context: AgentsToolContext) async throws -> String {
        try await CancelAgent(id: id).execute(in: context).successText()
    }
}
