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

    /// The run whose session holds the tool, or `nil` when the session is
    /// not a run, for example the root session of a host.
    let parent: ParentRun?

    /// Makes a context for a session that is not a run, for example the
    /// root session of a host.
    ///
    /// - Parameters:
    ///   - runner: The runner that owns each run that the tool starts.
    ///   - allowedNames: The names of `Agent(a, b)`, or `nil` for each
    ///     model-visible agent. The default is `nil`.
    public init(runner: AgentRunner, allowedNames: [String]? = nil) {
        self.init(runner: runner, allowedNames: allowedNames, parent: nil)
    }

    /// Makes a context.
    ///
    /// - Parameters:
    ///   - runner: The runner that owns each run that the tool starts.
    ///   - allowedNames: The names of `Agent(a, b)`, or `nil` for each
    ///     model-visible agent.
    ///   - parent: The run whose session holds the tool, or `nil` when the
    ///     session is not a run.
    init(runner: AgentRunner, allowedNames: [String]?, parent: ParentRun?) {
        self.runner = runner
        self.allowedNames = allowedNames
        self.parent = parent
    }

    /// The depth of a run that the tool starts (plan.md §9.3, depth): the
    /// depth of the calling run plus one, or ``AgentRunner/hostDepth`` when
    /// the session is not a run.
    var childDepth: Int {
        parent.map { $0.depth + 1 } ?? AgentRunner.hostDepth
    }

    /// The slot that `model: inherit`, or an absent `model`, selects for a
    /// run that the tool starts (plan.md §7).
    ///
    /// The rule: a child of a run uses the slot of the calling run. A run
    /// that a session starts, and the session is not a run (for example the
    /// root session of a host), uses ``AgentEnvironment/defaultSlot``. It
    /// does not use the slot of that session.
    var inheritedSlot: ModelSlot {
        parent?.slot ?? runner.environment.defaultSlot
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

    /// Finds the run `id` of the caller, and gives the answer of `body` for
    /// it.
    ///
    /// The caller is the session of `ToolContext.current`, or `nil` outside
    /// a Router session. A run of a different caller gives the same
    /// corrective as an id that no run has (plan.md §9.1), thus one caller
    /// cannot check or cancel the runs of another.
    ///
    /// - Parameters:
    ///   - id: The id that the model gave. The case of the letters does not
    ///     matter.
    ///   - body: Gives the answer for the run.
    /// - Returns: The answer of `body`, or a corrective with the ids of the
    ///   runs of the caller when no run of the caller has the id `id`.
    func answer(
        forRun id: String, _ body: (AgentRun) -> AgentsToolAnswer
    ) async -> AgentsToolAnswer {
        let caller = ToolContext.current?.sessionID
        guard let runID = ULID(ulidString: id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()),
            let run = await runner.run(id: runID),
            run.caller == caller
        else {
            let callerRuns = await runner.runs(caller: caller)
            return .corrective(AgentsToolText.unknownRun(id, ids: callerRuns.map(\.id.description)))
        }
        return body(run)
    }

    /// Gives the answer of `check agent` with no id: one block for each run
    /// of the caller, and only those runs.
    ///
    /// - Returns: The report of each run of the caller in id order, or "You
    ///   have no runs." Both are a success.
    func reportsOfCallerRuns() async -> AgentsToolAnswer {
        .success(AgentsToolText.reports(of: await runner.runs(caller: ToolContext.current?.sessionID)))
    }
}
