import Foundation
import FoundationModels
import FoundationModelsRouter
import ULID

/// The inputs of one agent run: what to run, for which caller, where in the
/// tree of runs, and in which folder.
struct AgentRunRequest: Sendable {
    /// Makes the `agents` tool of a run. It gets the run as a ``ParentRun``,
    /// the link to the caller of the run (`nil` when the run has no caller),
    /// the operations that the tool gives, and the names of `Agent(a, b)`, or
    /// `nil` for each agent.
    typealias AgentsToolMaker = @Sendable (
        ParentRun, AgentsToolContext.CallerLink?, AgentsToolContext.Grant, [String]?
    ) async throws -> any Tool

    /// The resolved agent. The run keeps it for its whole life.
    let definition: AgentDefinition

    /// The prompt of the run. It is `$ARGUMENTS` of the body and the first
    /// user prompt of the session.
    let prompt: String

    /// The context of the tool call that starts the run, or `nil` for a
    /// host-driven run. It gives the caller and the lineage.
    let context: ToolContext?

    /// The slot that `model: inherit` or an absent `model` selects: the slot
    /// of the calling run, or `AgentEnvironment.defaultSlot` when the caller
    /// is not a run.
    let inheritedSlot: ModelSlot

    /// The depth of the run. A host-started run has depth one, and a child
    /// has the depth of its parent plus one.
    let depth: Int

    /// The run that starts this run with its `agents` tool, or `nil` when
    /// the caller is not a run. The new run adds itself to the children of
    /// that run.
    var parent: ParentRun?

    /// Makes the `agents` tool of the run, or `nil` when the run cannot
    /// start agents.
    let agentsTool: AgentsToolMaker?

    /// The run of the Router session that starts this run, where the run
    /// sends the questions of its session (`SubagentQuestionTarget.current`
    /// of the `start agent` call), or `nil` for a host-driven run.
    ///
    /// The session of the run takes the user presence of the target. The
    /// target holds a strong reference to the calling session, thus the run
    /// keeps it only while it drives its session.
    var questionTarget: SubagentQuestionTarget? = nil

    /// The working folder that the start request names, or `nil` when the
    /// request names no folder. A host gives it to
    /// ``AgentRunner/start(_:prompt:workingDirectory:)``, and a model gives
    /// it in the `workingDirectory` field of `start agent`.
    var requestedDirectory: URL? = nil

    /// Gives the working folder of the run: the folder of the request
    /// (``requestedDirectory``), else the folder of the creator of the run.
    ///
    /// The creator is the session that starts the run. For a child run, the
    /// creator is the parent run, thus the child works on the files of the
    /// parent. A host session that is not a run, and the host API, give
    /// `environmentDirectory`: a `ToolContext` does not give the working
    /// folder of its session. A slash command gives the folder of its session
    /// as the folder of the request.
    ///
    /// An agent never works in its own folder by default, also an agent of
    /// the agent folder form. A host that wants a run in the folder of the
    /// agent gives ``AgentDefinition/folderURL`` as the folder of the
    /// request. The `AGENTS.md` documents of the run come from the folder
    /// that this gives.
    ///
    /// - Parameter environmentDirectory: The folder of a creator that is not
    ///   a run: ``AgentEnvironment/workingDirectory``.
    /// - Returns: The working folder of the run.
    func workingDirectory(default environmentDirectory: URL) -> URL {
        requestedDirectory ?? parent?.workingDirectory ?? environmentDirectory
    }

    /// The session id of the caller of a restored run, or `nil`. A restored
    /// run has a caller, but no live `start agent` call of that caller
    /// (``context`` is `nil`). The caller link of its `agents` tool then has
    /// the mail route.
    var restoredCaller: ULID? = nil

    /// Sends the final report of a restored run to its caller as mail, or
    /// `nil`. A restored run has no live `start agent` call that gives its
    /// result, thus the run mails the report when it ends.
    var resultMail: (@Sendable (String) async -> Void)? = nil

    /// The link from the `agents` tool of the run to its caller: the call
    /// route when a `start agent` call started the run, the mail route for
    /// a restored caller, else `nil` for a run with no caller.
    var callerLink: AgentsToolContext.CallerLink? {
        if let context {
            return AgentsToolContext.CallerLink(sessionID: context.sessionID, route: .call(context))
        }
        return restoredCaller.map { AgentsToolContext.CallerLink(sessionID: $0, route: .mail) }
    }

    /// Gives the same request with another prompt.
    ///
    /// - Parameter prompt: The new prompt.
    /// - Returns: The copy.
    func with(prompt: String) -> AgentRunRequest {
        var copy = AgentRunRequest(
            definition: definition, prompt: prompt, context: context, inheritedSlot: inheritedSlot, depth: depth,
            parent: parent, agentsTool: agentsTool, questionTarget: questionTarget,
            requestedDirectory: requestedDirectory)
        copy.restoredCaller = restoredCaller
        copy.resultMail = resultMail
        return copy
    }

    /// The lineage record of the session of the run: the session and the
    /// tool call that started the run, or `nil` for a host-driven run.
    var agentSpawn: SessionRecord.AgentSpawn? {
        context.map { context in
            SessionRecord.AgentSpawn(
                parentSessionId: context.sessionID, parentToolCallId: context.completionToken)
        }
    }
}
