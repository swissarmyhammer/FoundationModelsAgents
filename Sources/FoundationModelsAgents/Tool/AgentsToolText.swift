import FoundationModelsRouter

/// The plain-text answers of the `agents` tool (plan.md §9.1).
///
/// Each answer is text for the model. A corrective text tells the model what
/// was wrong and what it can do now, in the same turn.
enum AgentsToolText {
    /// The answer of `list agents` when no agent matches, and the end of a
    /// corrective when the tool can start no agent.
    static let noAgents = "No agents are available."

    /// The corrective of `start agent` with a prompt that holds no text.
    static let blankPrompt = """
        The prompt is blank. An agent sees only its prompt, so put the full task in the prompt.
        """

    /// The corrective of `start agent` after ``AgentRunner/stop()``, and the
    /// error text of `agents agent start` after that call.
    static let stopped = """
        The agent runner is stopped, and it starts no more agents. Do this part of the task yourself.
        """

    /// The error text of `agents agent start` before the first
    /// `AgentRegistry.load()`.
    static let catalogNotLoaded = """
        The agent catalog is not loaded. The host must call AgentRegistry.load() before it starts an agent.
        """

    /// The corrective of `send agent` and `send caller` with a message that
    /// holds no text.
    static let blankMessage = """
        The message is blank. Put the full text for the run in the message.
        """

    /// The corrective of `send caller` in a session that has no caller: a
    /// host session, or a run that a host started.
    static let noCaller = "You have no caller."

    /// The answer of `send caller`, and of `send agent` with the id of the
    /// caller, when the message was sent to the caller.
    static let messageSentToCaller = """
        The message was sent to the session that started you. Continue your work. \
        Your final message goes to that session when you end.
        """

    /// The answer of `check agent` with no id for a caller with no run, and
    /// the end of the unknown-id corrective for such a caller.
    static let noRuns = "You have no runs."

    /// The start of each message that a caller sends to a run that it
    /// started. It tells the model of the run where the message came from.
    static let callerMessagePrefix = "Message from your caller:"

    /// Gives the prompt of a message that a caller sends to a run that it
    /// started.
    ///
    /// - Parameter message: The text of the caller.
    /// - Returns: ``callerMessagePrefix``, a space, and `message`.
    static func callerMessage(_ message: String) -> String {
        "\(callerMessagePrefix) \(message)"
    }

    /// The text between two names or two ids of a list.
    private static let listSeparator = ", "

    /// The text between two run blocks of `check agent` with no id.
    private static let blockSeparator = "\n\n"

    /// Gives the corrective of `start agent` when the run limit is full
    /// (plan.md §9.3).
    ///
    /// - Parameter working: The count of runs that have a turn in operation.
    /// - Returns: "`N` agents are working now, and that is the limit." and
    ///   what the model can do now.
    static func atLimit(working: Int) -> String {
        """
        \(working) agents are working now, and that is the limit. \
        Do this part of the task yourself, or start the agent when one of them finishes.
        """
    }

    /// Gives the corrective of `start agent` when the new run would be deeper
    /// than ``AgentEnvironment/maxDepth`` (plan.md §9.3, depth).
    ///
    /// - Parameter maxDepth: The depth limit.
    /// - Returns: The corrective, with what the model can do now.
    static func atDepthLimit(maxDepth: Int) -> String {
        """
        You cannot start an agent here: a run that you start would be more than \(maxDepth) levels deep, \
        and that is the limit. Do this part of the task yourself.
        """
    }

    /// Gives the answer of `check agent` with no id: one block for each run
    /// of the caller.
    ///
    /// - Parameter runs: The runs of the caller, sorted by id.
    /// - Returns: The ``AgentRun/report`` of each run, with a blank line
    ///   between two reports, or ``noRuns`` when there is no run.
    static func reports(of runs: [AgentRun]) -> String {
        guard !runs.isEmpty else {
            return noRuns
        }
        return runs.lazy.map(\.report).joined(separator: blockSeparator)
    }

    /// Gives the answer of `start agent` outside a Router session, for a run
    /// in operation. No final message comes back to such a caller.
    ///
    /// - Parameter run: The run that the call started.
    /// - Returns: "Agent `name` started with the id `id`." and how to ask
    ///   about the run.
    static func started(_ run: AgentRun) -> String {
        "Agent \(run.agent.id) started with the id \(run.id). "
            + "Ask about it with {\"op\": \"check agent\", \"id\": \"\(run.id)\"}."
    }

    /// Gives the `next` sentence of the pending envelope of a call in a
    /// Router session.
    ///
    /// Only `start agent` is a background call. Its run works in the
    /// background, and its final message comes to the caller as mail. The
    /// pump of the Router delivers the mail only after the answer of the
    /// caller ends. Thus the sentence tells the model not to wait, not to
    /// guess the result, and to end its answer. It also tells the model how
    /// to ask about the run with the completion token of the call.
    ///
    /// - Parameter completionToken: The completion token of the call.
    /// - Returns: The sentence.
    static func collectInstruction(forCompletionToken completionToken: String) -> String {
        """
        This agent works in the background. Do not wait for it, and never guess its result. \
        End your answer now, or do other work first: its final message comes to you as a new message \
        after your answer ends. To see its state, call {"op": "check agent", "id": "\(completionToken)"}.
        """
    }

    /// Gives the corrective of `start agent` with a name that the catalog
    /// does not have, or that a reload removed.
    ///
    /// - Parameters:
    ///   - name: The name that the model gave.
    ///   - available: The names of the agents that the tool can start now.
    /// - Returns: The corrective, with the available names.
    static func unknownAgent(_ name: String, available: [String]) -> String {
        "No agent has the name \(name). \(availability(available))"
    }

    /// Gives the corrective of `start agent` with the name of an agent that
    /// `Agent(a, b)` does not permit.
    ///
    /// - Parameters:
    ///   - name: The name that the model gave.
    ///   - available: The names of the agents that the tool can start now.
    /// - Returns: The corrective, with the available names.
    static func notPermitted(_ name: String, available: [String]) -> String {
        "You cannot start the agent \(name). \(availability(available))"
    }

    /// Gives the corrective of `check agent`, `cancel agent`, or
    /// `send agent` with an id that no run of the caller has.
    ///
    /// - Parameters:
    ///   - id: The id that the model gave.
    ///   - ids: The ids of the runs of the caller.
    /// - Returns: The corrective, with the ids of the caller.
    static func unknownRun(_ id: String, ids: [String]) -> String {
        let known = ids.isEmpty
            ? noRuns
            : "The ids of your runs are: \(ids.joined(separator: listSeparator))."
        return "\(noRun(id)) \(known)"
    }

    /// Gives the sentence that no run has `id`.
    ///
    /// - Parameter id: The id that no run has.
    /// - Returns: "No run has the id `id`."
    private static func noRun(_ id: String) -> String {
        "No run has the id \(id)."
    }

    /// Gives the answer of `cancel agent`: the `CancelOutcome` of the run as
    /// text.
    ///
    /// For a run that ended before the cancel, the answer is "The run ended
    /// before the cancel.", then the detail of the final message. That
    /// detail is the report of the run, and it names the agent, thus the
    /// first sentence does not.
    ///
    /// - Parameters:
    ///   - outcome: What the cancel did.
    ///   - run: The run that the model cancelled.
    /// - Returns: The text of the outcome.
    static func cancel(_ outcome: CancelOutcome, of run: AgentRun) -> String {
        switch outcome {
        case .reported(let reported):
            "The cancel of \(run.subject) was sent (\(reported.rawValue)). The run stops when its turn ends."
        case .alreadySettled(let final):
            "The run ended before the cancel.\n\n\(final.detail)"
        case .unknownToken:
            noRun(run.id.description)
        }
    }

    /// Gives the answer of `send agent` when the run accepted the message.
    ///
    /// - Parameter run: The run that got the message.
    /// - Returns: "The message was sent to Agent `name` (`id`)." and where
    ///   the final message of the run comes.
    static func messageSent(to run: AgentRun) -> String {
        "The message was sent to \(run.subject). Its final message comes to you as mail."
    }

    /// Gives the corrective of `send agent` for a run that ended, or that
    /// started to end, before the message.
    ///
    /// - Parameters:
    ///   - id: The id of the run.
    ///   - state: The final state of the run.
    /// - Returns: "The run `id` ended (`state`), and it gets no more
    ///   messages." and what the model can do now.
    static func runEnded(id: String, state: AgentRunState) -> String {
        "The run \(id) ended (\(stateName(state))), and it gets no more messages. Start a new run."
    }

    /// Gives the one word that names `state`.
    ///
    /// - Parameter state: A state of a run.
    /// - Returns: `running`, `finished`, `failed`, or `cancelled`.
    private static func stateName(_ state: AgentRunState) -> String {
        switch state {
        case .running:
            "running"
        case .finished:
            "finished"
        case .failed:
            "failed"
        case .cancelled:
            "cancelled"
        }
    }

    /// Gives the sentence that names the agents that the tool can start.
    ///
    /// - Parameter names: The names, in catalog order.
    /// - Returns: The names, or ``noAgents`` when there are none.
    private static func availability(_ names: [String]) -> String {
        names.isEmpty
            ? noAgents
            : "The agents that you can start are: \(names.joined(separator: listSeparator))."
    }
}
