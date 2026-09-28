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

    /// The runs that the `start agent` calls of the tool started, by the
    /// completion token of each call.
    let startedRuns = StartedRuns()

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

    /// Gives the agents that the tool can start now and that match `filter`.
    ///
    /// The `list agents` operation of the tool and the `agent list` command
    /// of `AgentsCLI` use this function.
    ///
    /// - Parameter filter: Text that the name or the description of an agent
    ///   must hold. The case of the letters does not matter. A `nil` or blank
    ///   filter matches each agent.
    /// - Returns: Each agent of ``startableAgents()`` that matches, in catalog
    ///   order.
    func startableAgents(matching filter: String?) -> [AgentDefinition] {
        let text = filter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return startableAgents().filter { agent in
            text.isEmpty || agent.id.localizedCaseInsensitiveContains(text)
                || agent.description?.localizedCaseInsensitiveContains(text) == true
        }
    }

    /// Waits for `run`, and gives its final message text (plan.md §9.2).
    ///
    /// This is the background body of a `start agent` call in a Router
    /// session. The call adds the run to ``startedRuns`` under the completion
    /// token of `call`, thus the canceler of the call, `check agent`, and
    /// `cancel agent` find the run by that token. The add also ends the open
    /// call, thus each `check agent` and `cancel agent` that waits for the
    /// call continues. A cancel of the task of the body cancels the run.
    ///
    /// The Router answers the call with the pending envelope before the body
    /// ends, for each caller, thus the final message always comes as mail.
    ///
    /// - Parameters:
    ///   - run: The run that the call started.
    ///   - call: The context of the call.
    /// - Returns: The final message text of the run: the ``AgentRun/report``
    ///   of its final state.
    func finalMessage(of run: AgentRun, startedBy call: ToolContext) async -> String {
        startedRuns.add(run, forCall: call.completionToken)
        let final = await withTaskCancellationHandler {
            await run.finalState()
        } onCancel: {
            run.cancel()
        }
        return run.report(of: final)
    }

    /// Finds the run `id` of the caller, and gives the answer of `body` for
    /// it.
    ///
    /// The id is the id of a run, or the completion token of the
    /// `start agent` call that started the run: the pending envelope of that
    /// call holds the token. The caller is the session of
    /// `ToolContext.current`, or `nil` outside a Router session. A run of a
    /// different caller gives the same corrective as an id that no run has
    /// (plan.md §9.1), thus one caller cannot check or cancel the runs of
    /// another.
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
        guard let run = await run(named: id), run.caller == caller else {
            let callerRuns = await runner.runs(caller: caller)
            return .corrective(AgentsToolText.unknownRun(id, ids: callerRuns.map(\.id.description)))
        }
        return body(run)
    }

    /// Gives the answer of `check agent` with no id: one block for each run
    /// of the caller, and only those runs.
    ///
    /// The call first waits for each `start agent` call of the tool whose
    /// body did not add its run yet (``StartedRuns/waitForStarts()``). Thus a
    /// run that the model started in its pass before is in the answer.
    ///
    /// - Returns: The report of each run of the caller in id order, or "You
    ///   have no runs." Both are a success.
    func reportsOfCallerRuns() async -> AgentsToolAnswer {
        await startedRuns.waitForStarts()
        return .success(AgentsToolText.reports(of: await runner.runs(caller: ToolContext.current?.sessionID)))
    }

    /// Finds the run that `id` names: the run with that id, or the run that
    /// the `start agent` call with that completion token started.
    ///
    /// When `id` is the token of a `start agent` call whose body did not add
    /// its run yet, the call first waits for that body
    /// (``StartedRuns/waitForStart(ofCall:)``).
    ///
    /// - Parameter id: The id that the model gave.
    /// - Returns: The run, or `nil` when `id` names no run.
    private func run(named id: String) async -> AgentRun? {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        await startedRuns.waitForStart(ofCall: key)
        if let runID = ULID(ulidString: key), let run = await runner.run(id: runID) {
            return run
        }
        return startedRuns.run(forCall: key)
    }
}
