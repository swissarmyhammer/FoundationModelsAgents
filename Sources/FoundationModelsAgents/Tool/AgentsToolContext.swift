import Foundation
import FoundationModelsRouter
import ULID

/// The shared environment of the operations of the `agents` tool.
///
/// `AgentsTool.make(context:catalogCharacterLimit:)` reads the catalog of
/// `runner` one time. The operations use `runner` to start, check, and cancel
/// runs, and to send messages to them. They use `callerLink` to send a
/// message to the caller of the run.
public struct AgentsToolContext: Sendable {
    /// The link from the tool of a run to the caller of that run: the
    /// session that started the run.
    struct CallerLink: Sendable {
        /// The context of the `start agent` call in the session of the
        /// caller. It is the ``AgentRun/context`` of the run.
        let call: ToolContext

        /// The id of the session of the caller. It is the
        /// ``AgentRun/caller`` of the run.
        let sessionID: ULID
    }

    /// The operations that the tool gives.
    enum Grant: Sendable {
        /// Each operation: list, start, check, and cancel agents, and the
        /// message operations.
        case full

        /// Only the message operations. The tool does not read the catalog,
        /// and its description names no agent.
        case messagingOnly
    }

    /// The runner that owns each run that the tool starts.
    public let runner: AgentRunner

    /// The names of `Agent(a, b)`: the only agents that the tool can start.
    /// `nil` when the tool can start each model-visible agent.
    public let allowedNames: [String]?

    /// The run whose session holds the tool, or `nil` when the session is
    /// not a run, for example the root session of a host.
    let parent: ParentRun?

    /// The link to the caller of the run whose session holds the tool, or
    /// `nil` when the run has no caller. A host session and a host-started
    /// run have no caller.
    let callerLink: CallerLink?

    /// The operations that the tool gives.
    let grant: Grant

    /// The runs that the `start agent` calls of the tool started, by the
    /// completion token of each call.
    let startedRuns = StartedRuns()

    /// Makes a context for a session that is not a run, for example the
    /// root session of a host. The tool gives each operation.
    ///
    /// - Parameters:
    ///   - runner: The runner that owns each run that the tool starts.
    ///   - allowedNames: The names of `Agent(a, b)`, or `nil` for each
    ///     model-visible agent. The default is `nil`.
    public init(runner: AgentRunner, allowedNames: [String]? = nil) {
        self.init(runner: runner, allowedNames: allowedNames, parent: nil, callerLink: nil, grant: .full)
    }

    /// Makes a context.
    ///
    /// - Parameters:
    ///   - runner: The runner that owns each run that the tool starts.
    ///   - allowedNames: The names of `Agent(a, b)`, or `nil` for each
    ///     model-visible agent.
    ///   - parent: The run whose session holds the tool, or `nil` when the
    ///     session is not a run.
    ///   - callerLink: The link to the caller of that run, or `nil` when the
    ///     run has no caller.
    ///   - grant: The operations that the tool gives.
    init(
        runner: AgentRunner, allowedNames: [String]?, parent: ParentRun?, callerLink: CallerLink?, grant: Grant
    ) {
        self.runner = runner
        self.allowedNames = allowedNames
        self.parent = parent
        self.callerLink = callerLink
        self.grant = grant
    }

    /// The depth of a run that the tool starts: the depth of the calling run
    /// plus one, or ``AgentRunner/hostDepth`` when the session is not a run.
    var childDepth: Int {
        parent.map { $0.depth + 1 } ?? AgentRunner.hostDepth
    }

    /// The slot that `model: inherit`, or an absent `model`, selects for a
    /// run that the tool starts.
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
    /// The tool of a run cannot start the agent of that run
    /// (``isOwnAgent(_:)``). Thus the description, `list agents`, and the
    /// `name` enum of the tool do not hold that agent, and the model of the
    /// run cannot give its own task to a new run of its own agent.
    ///
    /// - Parameter definition: An agent of the catalog.
    /// - Returns: `true` when the model can see the agent, the allowed names,
    ///   if any, hold its id, and it is not the agent of the run.
    func canStart(_ definition: AgentDefinition) -> Bool {
        definition.isModelVisible && (allowedNames?.contains(definition.id) ?? true)
            && !isOwnAgent(definition.id)
    }

    /// Tells whether `name` is the agent of the run whose session holds the
    /// tool.
    ///
    /// - Parameter name: The id of an agent.
    /// - Returns: `true` when the session is a run of the agent `name`. A
    ///   session that is not a run, for example a host root session, has no
    ///   own agent.
    func isOwnAgent(_ name: String) -> Bool {
        parent?.agentID == name
    }

    /// Tells whether `id` is the id of the run whose session holds the tool.
    ///
    /// A run id is the id of its session, thus the session of
    /// `ToolContext.current` names the run that makes the call.
    ///
    /// - Parameter id: The id that the model gave. White space at the start
    ///   or the end, and the case of the letters, do not matter.
    /// - Returns: `true` when the session is a run and `id` names it.
    func isOwnRun(_ id: String) -> Bool {
        guard parent != nil, let sessionID = ToolContext.current?.sessionID else {
            return false
        }
        return ULID(ulidString: Self.key(of: id)) == sessionID
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
    /// The `list agents` operation of the tool uses this function.
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

    /// Waits for `run`, and gives its final message text.
    ///
    /// This is the background body of a `start agent` call in a Router
    /// session. The call adds the run to ``startedRuns`` under the completion
    /// token of `call`, thus the canceler of the call, `check agent`, and
    /// `cancel agent` find the run by that token. The add also ends the open
    /// call, thus each `check agent` and `cancel agent` that waits for the
    /// call continues. A cancel of the task of the body cancels the run.
    ///
    /// When the run ends in the settle period of the session, the Router
    /// gives this text to the model as the answer of the call. Else the
    /// Router answers the call with the pending envelope before the body
    /// ends, and the final message comes as mail.
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
    /// different caller gives the same corrective as an id that no run has,
    /// thus one caller cannot check, cancel, or send a message to the runs
    /// of another.
    ///
    /// - Parameters:
    ///   - id: The id that the model gave. The case of the letters does not
    ///     matter.
    ///   - body: Gives the answer for the run. It can wait, for example for
    ///     ``AgentRun/deliver(_:)``.
    /// - Returns: The answer of `body`, or a corrective with the ids of the
    ///   runs of the caller when no run of the caller has the id `id`.
    func answer(
        forRun id: String, _ body: (AgentRun) async -> AgentsToolAnswer
    ) async -> AgentsToolAnswer {
        let caller = ToolContext.current?.sessionID
        guard let run = await run(named: id), run.caller == caller else {
            let callerRuns = await runner.runs(caller: caller)
            return .corrective(AgentsToolText.unknownRun(id, ids: callerRuns.map(\.id.description)))
        }
        return await body(run)
    }

    /// Tells whether `id` is the id of the session of the caller.
    ///
    /// A run id is the id of its session, thus the id of a parent run is
    /// the id of the caller of its child.
    ///
    /// - Parameter id: The id that the model gave. White space at the start
    ///   or the end, and the case of the letters, do not matter.
    /// - Returns: `true` when the run has a caller and `id` names its
    ///   session.
    func isCaller(_ id: String) -> Bool {
        guard let callerLink else {
            return false
        }
        return ULID(ulidString: Self.key(of: id)) == callerLink.sessionID
    }

    /// Sends `message` to the caller of the run (`send caller`).
    ///
    /// The message goes out as a `message` event of the `start agent` call
    /// that started the run. The caller session gets it as mail, and the
    /// Router starts an answer for it. The run continues, and its final
    /// message still goes to the caller when it ends.
    ///
    /// A sent message gives one `agent.message.sent` record with the
    /// `delivered` outcome, and a run with no caller gives one with the
    /// `no_caller` outcome (``recordMessageToCaller(_:outcome:)``). A blank
    /// message sends nothing and gives no record.
    ///
    /// - Parameter message: The text of the message.
    /// - Returns: ``AgentsToolText/messageSentToCaller`` when the message was
    ///   sent. A corrective for a run with no caller, or for a message that
    ///   holds no text.
    func messageCaller(_ message: String) async -> AgentsToolAnswer {
        guard let callerLink else {
            await recordMessageToCaller(message, outcome: .noCaller)
            return .corrective(AgentsToolText.noCaller)
        }
        if let corrective = Self.blankMessageCorrective(message) {
            return corrective
        }
        await callerLink.call.message(message)
        await recordMessageToCaller(message, outcome: .delivered)
        return .success(AgentsToolText.messageSentToCaller)
    }

    /// Gives the corrective of `send agent` and `send caller` for a message
    /// that holds no text. This is the one blank-message check of the two
    /// operations.
    ///
    /// - Parameter message: The text of the message.
    /// - Returns: ``AgentsToolText/blankMessage`` as a corrective when
    ///   `message` holds no text, or `nil` when it holds text.
    static func blankMessageCorrective(_ message: String) -> AgentsToolAnswer? {
        guard AgentDefinitionRules.holdsText(message) else {
            return .corrective(AgentsToolText.blankMessage)
        }
        return nil
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
        let key = Self.key(of: id)
        await startedRuns.waitForStart(ofCall: key)
        if let runID = ULID(ulidString: key), let run = await runner.run(id: runID) {
            return run
        }
        return startedRuns.run(forCall: key)
    }

    /// Gives the form of an id that the model gave, in which it is compared
    /// with the id of a run, of a session, or of a call.
    ///
    /// A ULID and a completion token are Crockford base 32, thus the case of
    /// the letters does not matter.
    ///
    /// - Parameter id: The id that the model gave.
    /// - Returns: `id` with no white space at the start or the end, in upper
    ///   case.
    private static func key(of id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
