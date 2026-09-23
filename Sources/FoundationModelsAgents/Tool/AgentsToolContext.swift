import Foundation
import FoundationModelsRouter
import ULID

/// The shared environment of the four operations of the `agents` tool
/// (plan.md §9.1).
///
/// `AgentsTool.make(context:catalogCharacterLimit:)` reads the catalog of
/// `runner` one time. The operations use `runner` to start, check, and cancel
/// runs.
public struct AgentsToolContext: Sendable {
    /// The runner that owns each run that the tool starts.
    public let runner: AgentRunner

    /// The names of `Agent(a, b)`: the only agents that the tool can start.
    /// `nil` when the tool can start each model-visible agent.
    public let allowedNames: [String]?

    /// Makes a context.
    ///
    /// - Parameters:
    ///   - runner: The runner that owns each run that the tool starts.
    ///   - allowedNames: The names of `Agent(a, b)`, or `nil` for each
    ///     model-visible agent. The default is `nil`.
    public init(runner: AgentRunner, allowedNames: [String]? = nil) {
        self.runner = runner
        self.allowedNames = allowedNames
    }

    /// Tells whether the tool can start `definition`.
    ///
    /// - Parameter definition: An agent of the catalog.
    /// - Returns: `true` when the model can see the agent and the allowed
    ///   names, if any, hold its id.
    func canStart(_ definition: AgentDefinition) -> Bool {
        definition.isModelVisible && (allowedNames?.contains(definition.id) ?? true)
    }

    /// Gives the agents that the tool can start now.
    ///
    /// The call reads the catalog of `runner` again, thus a reload shows: a
    /// changed agent has its new definition, and a removed agent is not
    /// there.
    ///
    /// - Returns: Each agent of the catalog that ``canStart(_:)`` permits, in
    ///   catalog order.
    func startableAgents() -> [AgentDefinition] {
        runner.catalog().definitions.filter(canStart)
    }

    /// Finds the run `id`, and gives the answer of `body` for it.
    ///
    /// - Parameters:
    ///   - id: The id that the model gave. The case of the letters does not
    ///     matter.
    ///   - body: Gives the answer for the run.
    /// - Returns: The answer of `body`, or a corrective with the ids of the
    ///   runs of the caller when no run has the id `id`.
    func answer(
        forRun id: String, _ body: (AgentRun) -> AgentsToolAnswer
    ) async -> AgentsToolAnswer {
        guard let runID = ULID(ulidString: id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()),
            let run = await runner.run(id: runID)
        else {
            let callerRuns = await runner.runs(caller: ToolContext.current?.sessionID)
            return .corrective(AgentsToolText.unknownRun(id, ids: callerRuns.map(\.id.description)))
        }
        return body(run)
    }
}
