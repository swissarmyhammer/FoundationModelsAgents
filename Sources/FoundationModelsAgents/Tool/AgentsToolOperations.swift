import FoundationModels
import FoundationModelsSkills
import Operations

/// The answers of the four operations of the `agents` tool.
///
/// Each answer is plain text: `.success` or `.corrective(String)`
/// (plan.md §9.1). A correction is a text result in the same turn, never a
/// thrown error.
typealias AgentsToolAnswer = CorrectiveOutcome<String>

extension AgentsToolAnswer {
    /// The answer of an operation whose body is not written yet. The
    /// operations task of plan.md §9.1 replaces each use.
    static var notImplemented: AgentsToolAnswer {
        .corrective("not implemented")
    }
}

/// Lists the agents that the model can start (`list agents`).
@Generable
@Operation(verb: "list", noun: "agents", description: "List each agent that you can start, with its description.")
struct ListAgents {
    /// Text that the name or the description of an agent must hold.
    @Guide(description: "Case-insensitive text to find in the name or the description of an agent.")
    var filter: String?
}

extension ListAgents {
    /// Gives the agents that match `filter`.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The answer of the operation.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        .notImplemented
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
    /// Starts the agent `name` with `prompt`.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The answer of the operation.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        .notImplemented
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
    /// Gives the state of the run `id`.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The answer of the operation.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        .notImplemented
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
    /// Cancels the run `id`.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The answer of the operation.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        .notImplemented
    }
}
