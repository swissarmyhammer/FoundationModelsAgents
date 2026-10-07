import Foundation
import FoundationModels
import FoundationModelsRouter
import FoundationModelsSkills
import Operations

/// The answers of the operations of the `agents` tool.
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
        let matches = context.startableAgents(matching: filter)
        guard !matches.isEmpty else {
            return .success(AgentsToolText.noAgents)
        }
        let lines = AgentsToolDescription.lines(for: matches.map(AgentsToolDescription.Entry.init))
        return .success(lines + "\n\n" + AgentsToolDescription.delegationSentence)
    }
}

/// Starts an agent on a task (`start agent`).
///
/// The one background operation of the tool: in a Router session each call
/// answers at once with the pending envelope, and the final message of the
/// run comes later as mail. The other operations keep the default
/// synchronous mount and answer in band.
@Generable
@Operation(
    verb: "start", noun: "agent",
    description: "Start an agent on a task. The call returns at once with the id of the run.",
    mount: ToolMount(mode: .background))
struct StartAgent {
    /// The name of the agent to start.
    @Guide(description: "The name of the agent to start.")
    var name: String

    /// The full task for the agent.
    @Guide(description: "The full task. The agent sees only this text.")
    var prompt: String
}

extension StartAgent {
    /// Starts the agent `name` with `prompt`.
    ///
    /// The run gets `ToolContext.current`, the context of this call. In a
    /// Router session this call is the background body of the call: it waits
    /// for the run, and gives the final message text of the run as its
    /// answer (``AgentsToolContext/finalMessage(of:startedBy:)``). The Router
    /// answers the model at once with the pending envelope, also when the run
    /// ends at once, and delivers the final message later as mail
    /// (plan.md §9.2). Outside a Router session there is no context: the call
    /// returns at once with the id of the run, and the model uses
    /// `check agent`.
    ///
    /// The call reads the catalog again, thus after a reload a changed agent
    /// runs with its new definition, and a removed agent gives a corrective.
    ///
    /// Only this operation checks ``AgentEnvironment/maxConcurrentAgents``
    /// (plan.md §9.3). At the limit it starts no run, and there is no queue.
    ///
    /// The new run gets the depth of the calling run plus one, and the slot
    /// of the calling run for `model: inherit`. A session that is not a run
    /// gives depth one and ``AgentEnvironment/defaultSlot``. Above
    /// ``AgentEnvironment/maxDepth`` the call starts no run. The new run gets
    /// an `agents` tool of its own only when its `tools` key has an explicit
    /// `Agent`, `Agent(a, b)`, or `agents` entry.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The final message text of the run in a Router session, or
    ///   the id of the run outside one. The report of a run whose setup
    ///   failed. A corrective for a blank prompt, for a name that the tool
    ///   cannot start, for a name that no agent has, for a depth above the
    ///   limit, for a full run limit, or for a runner that
    ///   ``AgentRunner/stop()`` stopped.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        guard AgentDefinitionRules.holdsText(prompt) else {
            return .corrective(AgentsToolText.blankPrompt)
        }
        let startable = context.startableAgents()
        guard let definition = startable.first(where: { $0.id == name }) else {
            return .corrective(unavailableText(startable: startable.map(\.id), in: context))
        }
        let runner = context.runner
        let maxDepth = runner.environment.maxDepth
        guard context.childDepth <= maxDepth else {
            return .corrective(AgentsToolText.atDepthLimit(maxDepth: maxDepth))
        }
        let callContext = ToolContext.current
        let start = await runner.startWithinLimit(
            AgentRunRequest(
                definition: definition, prompt: prompt, context: callContext,
                inheritedSlot: context.inheritedSlot, depth: context.childDepth, parent: context.parent,
                agentsTool: AgentRun.agentsTool(of: runner)))
        switch start {
        case .atLimit(let working):
            return .corrective(AgentsToolText.atLimit(working: working))
        case .stopped:
            return .corrective(AgentsToolText.stopped)
        case .started(let run):
            guard !run.isSetupFailure else {
                return .success(run.report)
            }
            guard let callContext else {
                return .success(AgentsToolText.started(run))
            }
            return .success(await context.finalMessage(of: run, startedBy: callContext))
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
    /// when there is no `id`. The call never waits for a run to end. It
    /// waits only for a `start agent` call of the pass before whose body did
    /// not add its run yet, thus it finds the run of that call.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The report of the run: running with its last event and,
    ///   after its task turn, the count of open runs that it started;
    ///   finished with the full text; failed with the reason; or cancelled.
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
    /// When `id` is the token of a `start agent` call whose body did not add
    /// its run yet, the call first waits for that body, thus it cancels the
    /// run of that call.
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

/// Sends a message to a run that the caller started (`send agent`).
@Generable
@Operation(
    verb: "send", noun: "agent",
    description: "Send a message to a run that you started. The run answers it before it ends.")
struct SendAgent {
    /// The id of the run that gets the message.
    @Guide(description: "The id of the run that gets the message.")
    var id: String

    /// The text of the message.
    @Guide(description: "The full text of the message. The run sees only this text.")
    var message: String
}

extension SendAgent {
    /// Sends `message` to the run `id` of the caller (``AgentRun/deliver(_:)``).
    ///
    /// The id is the id of the run, or the completion token of the
    /// `start agent` call that started it. When that call did not add its
    /// run yet, the call first waits for it, the same as `check agent`. A
    /// run that accepts the message answers it before it ends, and its final
    /// message comes to the caller as mail.
    ///
    /// When `id` is the id of the session that started the run of this
    /// tool, the call does the same as `send caller`
    /// (``AgentsToolContext/messageCaller(_:)``). A run id is the id of its
    /// session, thus the id of the parent run names the caller.
    ///
    /// Each message that goes to a run, or that a run refuses because it
    /// ended, gives one `agent.message.sent` record with the `to_run`
    /// direction. A message to the caller gives the `to_caller` record of
    /// `send caller`. A blank message and an unknown id send nothing and give
    /// no record.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The sent text when the run or the caller accepted the
    ///   message. A corrective for a blank message, for a run that ended, or
    ///   for an id that names no run of the caller and not the caller.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        if let corrective = AgentsToolContext.blankMessageCorrective(message) {
            return corrective
        }
        guard !context.isCaller(id) else {
            return await context.messageCaller(message)
        }
        return await context.answer(forRun: id) { run in await deliver(to: run, in: context) }
    }

    /// Gives `message` to `run`, and records the message: one
    /// `agent.message.sent` log record and span event with the `to_run`
    /// direction (``AgentsToolContext/record(_:)``).
    ///
    /// - Parameters:
    ///   - run: A run of the caller.
    ///   - context: The shared context of the tool.
    /// - Returns: The sent text when the run accepted the message, or the
    ///   corrective for a run that ended.
    private func deliver(to run: AgentRun, in context: AgentsToolContext) async -> AgentsToolAnswer {
        let outcome = await run.deliver(message)
        context.record(
            AgentMessageRecord(
                direction: .toRun, run: run, outcome: AgentsTelemetry.MessageOutcome(outcome), length: message.count))
        switch outcome {
        case .delivered:
            return .success(AgentsToolText.messageSent(to: run))
        case .ended(let state):
            return .corrective(AgentsToolText.runEnded(id: run.id.description, state: state))
        }
    }
}

/// Sends a message to the session that started the run (`send caller`).
///
/// The noun alias `parent` gives this operation, thus `send parent` is the
/// same call.
@Generable
@Operation(
    verb: "send", noun: "caller",
    description: """
        Send a message to the session that started you. You continue to work. \
        Your final message still goes to it when you end.
        """)
struct SendCaller {
    /// The text of the message.
    @Guide(description: "The full text of the message. The session that started you sees only this text.")
    var message: String
}

extension SendCaller {
    /// Sends `message` to the caller of the run
    /// (``AgentsToolContext/messageCaller(_:)``). The caller gets it as
    /// mail, and the run continues. `messageCaller(_:)` writes the one
    /// `agent.message.sent` record of the call, with the `to_caller`
    /// direction, because `send agent` with the id of the caller uses it too.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The sent text. A corrective for a run with no caller, or
    ///   for a blank message.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        await context.messageCaller(message)
    }
}
