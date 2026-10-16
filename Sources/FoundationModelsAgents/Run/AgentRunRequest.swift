import Foundation
import FoundationModels
import FoundationModelsRouter

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
    let parent: ParentRun?

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

    /// The folder of the agent when the agent-folder source gave it, or
    /// `nil` for an agent of the dotfolder stack.
    ///
    /// The folder of a dotfolder-stack agent (`agents/<id>/` of the
    /// marketplace, defaults, user, or project layer) holds a definition in a
    /// configuration folder, thus a run of that agent never works in it.
    private var agentFolder: URL? {
        definition.kind.isInAgentFolderSource ? definition.folderURL : nil
    }

    /// Gives the working folder of the run: the first of the folder of the
    /// request (``requestedDirectory``), the folder of the parent run, the
    /// folder of an agent of the agent-folder source, and
    /// `environmentDirectory`.
    ///
    /// A parent that gives a task expects the child to work on the files of
    /// the parent, thus the folder of the parent comes before the folder of
    /// the agent. The folder of the agent is the default of a root run that
    /// names no folder. The `AGENTS.md` documents of the run come from the
    /// folder that this gives.
    ///
    /// - Parameter environmentDirectory: The folder of a run that has no
    ///   other folder: ``AgentEnvironment/workingDirectory``.
    /// - Returns: The working folder of the run.
    func workingDirectory(default environmentDirectory: URL) -> URL {
        requestedDirectory ?? parent?.workingDirectory ?? agentFolder ?? environmentDirectory
    }

    /// The lineage record of the session of the run: the session and the
    /// tool call that started the run, or `nil` for a host-driven run.
    var agentSpawn: SessionSidecar.AgentSpawn? {
        context.map { context in
            SessionSidecar.AgentSpawn(
                parentSessionId: context.sessionID, parentToolCallId: context.completionToken)
        }
    }
}
