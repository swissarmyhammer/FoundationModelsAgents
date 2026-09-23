import FoundationModelsRouter

/// The inputs of one agent run: what to run, for which caller, and where in
/// the tree of runs (plan.md §8, §8.2).
struct AgentRunRequest: Sendable {
    /// The resolved agent. The run keeps it for its whole life.
    let definition: AgentDefinition

    /// The prompt of the run. It is `$ARGUMENTS` of the body and the first
    /// user prompt of the session.
    let prompt: String

    /// The context of the tool call that starts the run, or `nil` for a
    /// host-driven run. It gives the caller and the lineage.
    let context: ToolContext?

    /// The slot that `model: inherit` or an absent `model` selects: the slot
    /// of the caller, or `AgentEnvironment.defaultSlot` for a host-started
    /// run.
    let inheritedSlot: ModelSlot

    /// The depth of the run. A host-started run has depth one.
    let depth: Int

    /// Makes the `agents` tool of the run, or `nil` when the run cannot
    /// start agents.
    let agentsTool: ToolResolver.AgentsToolFactory?

    /// The lineage record of the session of the run (plan.md §8.2): the
    /// session and the tool call that started the run, or `nil` for a
    /// host-driven run.
    var agentSpawn: SessionSidecar.AgentSpawn? {
        context.map { context in
            SessionSidecar.AgentSpawn(
                parentSessionId: context.sessionID, parentToolCallId: context.completionToken)
        }
    }
}
