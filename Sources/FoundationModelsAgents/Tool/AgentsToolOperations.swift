import Foundation
import FoundationModels
import FoundationModelsRouter
import FoundationModelsSkills
import Operations

/// The answers of the four operations of the `agents` tool.
///
/// Each answer is plain text: `.success` or `.corrective(String)`
/// (plan.md §9.1). A correction is a text result in the same turn, never a
/// thrown error, and never a post. `AgentsTool` decodes the JSON string that
/// `OperationTool` makes of the answer, thus the model reads plain text.
typealias AgentsToolAnswer = CorrectiveOutcome<String>

/// Lists the agents that the model can start (`list agents`).
@Generable
@Operation(verb: "list", noun: "agents", description: "List each agent that you can start, with its description.")
struct ListAgents {
    /// Text that the name or the description of an agent must hold.
    @Guide(description: "Case-insensitive text to find in the name or the description of an agent.")
    var filter: String?
}

extension ListAgents {
    /// Gives one `- name: description` line for each agent that the tool
    /// can start and that matches `filter`, then the delegation sentence.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The lines and the delegation sentence, or "No agents are
    ///   available." when no agent matches. Both are a success.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        let text = filter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let matches = context.startableAgents().filter { agent in
            text.isEmpty || agent.id.localizedCaseInsensitiveContains(text)
                || agent.description?.localizedCaseInsensitiveContains(text) == true
        }
        guard !matches.isEmpty else {
            return .success(AgentsToolText.noAgents)
        }
        let lines = AgentsToolDescription.lines(
            for: matches.map { AgentsToolDescription.Entry(name: $0.id, description: $0.description) })
        return .success(lines + "\n\n" + AgentsToolDescription.delegationSentence)
    }
}

/// Starts an agent on a task (`start agent`).
@Generable
@Operation(
    verb: "start", noun: "agent",
    description: "Start an agent on a task. The call returns at once with the id of the run.")
struct StartAgent {
    /// The name of the agent to start.
    @Guide(description: "The name of the agent to start.")
    var name: String

    /// The full task for the agent.
    @Guide(description: "The full task. The agent sees only this text.")
    var prompt: String
}

extension StartAgent {
    /// Starts the agent `name` with `prompt`, and returns at once.
    ///
    /// The run gets `ToolContext.current`, the context of this call. The
    /// runner maps the `completionToken` of the call to the run. The call
    /// posts nothing: the run posts its final message through the context
    /// when it finishes (plan.md §9.2). Outside a Router session there is no
    /// context, the run posts nothing, and the model uses `check agent`.
    ///
    /// The call reads the catalog again, thus after a reload a changed agent
    /// runs with its new definition, and a removed agent gives a corrective.
    ///
    /// Only this operation checks ``AgentEnvironment/maxConcurrentAgents``
    /// (plan.md §9.3). At the limit it starts no run, and there is no queue.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The id of the run, or a corrective for a blank prompt, for
    ///   a name that the tool cannot start, for a name that no agent has, or
    ///   for a full run limit.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        guard AgentDefinitionRules.holdsText(prompt) else {
            return .corrective(AgentsToolText.blankPrompt)
        }
        let startable = context.startableAgents()
        guard let definition = startable.first(where: { $0.id == name }) else {
            return .corrective(unavailableText(startable: startable.map(\.id), in: context))
        }
        let callContext = ToolContext.current
        let runner = context.runner
        let start = await runner.startWithinLimit(
            AgentRunRequest(
                definition: definition, prompt: prompt, context: callContext,
                inheritedSlot: runner.environment.defaultSlot, depth: AgentRunner.hostDepth, agentsTool: nil))
        switch start {
        case .atLimit(let working):
            return .corrective(AgentsToolText.atLimit(working: working))
        case .started(let run):
            return .success(run.isSetupFailure
                ? run.report : AgentsToolText.started(run, postsFinalMessage: callContext != nil))
        }
    }

    /// Gives the corrective for a name that the tool cannot start.
    ///
    /// - Parameters:
    ///   - startable: The names of the agents that the tool can start now.
    ///   - context: The shared context of the tool.
    /// - Returns: The not-permitted corrective when the catalog has a
    ///   model-visible agent `name` that `Agent(a, b)` does not permit.
    ///   Otherwise the unknown-agent corrective.
    private func unavailableText(startable: [String], in context: AgentsToolContext) -> String {
        let isVisible = context.runner.catalog().definition(named: name)?.isModelVisible == true
        return isVisible
            ? AgentsToolText.notPermitted(name, available: startable)
            : AgentsToolText.unknownAgent(name, available: startable)
    }
}

/// Gives the state of a run (`check agent`).
@Generable
@Operation(verb: "check", noun: "agent", description: "Get the state of a run. The call never waits.")
struct CheckAgent {
    /// The id of the run, or `nil` for each run of the caller.
    @Guide(description: "The id of the run. With no id, you get each run that you started.")
    var id: String?
}

extension CheckAgent {
    /// Gives the state of the run `id` at once, or of each run of the caller
    /// when there is no `id`. The call never waits for a run.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The report of the run: running with its last event,
    ///   finished with the full text, failed with the reason, or cancelled.
    ///   With no `id`, one report for each run of the caller. A corrective
    ///   for an id that no run of the caller has.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        guard let id else {
            return await context.reportsOfCallerRuns()
        }
        return await context.answer(forRun: id) { run in .success(run.report) }
    }
}

/// Cancels a run (`cancel agent`).
@Generable
@Operation(verb: "cancel", noun: "agent", description: "Cancel a run and the runs that it started.")
struct CancelAgent {
    /// The id of the run to cancel.
    @Guide(description: "The id of the run to cancel.")
    var id: String
}

extension CancelAgent {
    /// Cancels the run `id`, and gives the `CancelOutcome` as text.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The text of the `CancelOutcome`, or a corrective for an id
    ///   that no run of the caller has.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        await context.answer(forRun: id) { run in
            .success(AgentsToolText.cancel(run.requestCancel(), of: run))
        }
    }
}
