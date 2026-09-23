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

    /// The answer of `check agent` with no id for a caller with no run, and
    /// the end of the unknown-id corrective for such a caller.
    static let noRuns = "You have no runs."

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

    /// Gives the answer of `start agent` for a run in operation.
    ///
    /// - Parameters:
    ///   - run: The run that the call started.
    ///   - postsFinalMessage: `true` when the call has a `ToolContext`, thus
    ///     the final message of the run comes back to the caller.
    /// - Returns: "Agent `name` started with the id `id`." and how the
    ///   result comes back.
    static func started(_ run: AgentRun, postsFinalMessage: Bool) -> String {
        let start = "Agent \(run.agent.id) started with the id \(run.id)."
        guard postsFinalMessage else {
            return start + " Ask about it with {\"op\": \"check agent\", \"id\": \"\(run.id)\"}."
        }
        return start + " Its final message comes to you when it finishes."
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

    /// Gives the corrective of `check agent` or `cancel agent` with an id
    /// that no run has.
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
    /// - Parameters:
    ///   - outcome: What the cancel did.
    ///   - run: The run that the model cancelled.
    /// - Returns: The text of the outcome.
    static func cancel(_ outcome: CancelOutcome, of run: AgentRun) -> String {
        switch outcome {
        case .reported(let reported):
            "The cancel of \(run.subject) was sent (\(reported.rawValue)). The run stops when its turn ends."
        case .alreadySettled(let final):
            "\(run.subject) ended before the cancel.\n\n\(final.detail)"
        case .unknownToken:
            noRun(run.id.description)
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
