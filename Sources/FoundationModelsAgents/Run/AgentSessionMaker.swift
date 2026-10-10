import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter

/// Makes the session of one agent run, in these steps:
///
/// 1. Render the body with the prompt as `$ARGUMENTS`.
/// 2. Put the instructions in order: the `AGENTS.md` files of the working
///    directory, outermost first, then the rendered body, then the rendered
///    body of each skill of the `skills` key, in the order of the key
///    (``AgentSkillsPreload``).
/// 3. Resolve the tools.
/// 4. Match the model, and make the session on the slot of the match.
///
/// The model match comes before the tools, because the `agents` tool of the
/// run gives the slot of the run to each child with `model: inherit`. Each
/// step that fails stops the run before it makes a session.
struct AgentSessionMaker: Sendable {
    /// The session of a run and the slot that it runs on.
    struct Made {
        /// The new session. The run holds it and closes it.
        let session: any RoutedSession

        /// The slot of the model of the session.
        let slot: ModelSlot
    }

    /// The text between two parts of the instructions.
    static let instructionsSeparator = "\n\n"

    /// The dependencies and the limits of the runs.
    let environment: AgentEnvironment

    /// Renders the body of each agent.
    let renderer: AgentBodyRenderer

    /// Makes the session of the run of `request`.
    ///
    /// - Parameters:
    ///   - request: The run to make the session for.
    ///   - family: The children of the new run. The `agents` tool of the run
    ///     adds to the children.
    /// - Returns: The new session and its slot.
    /// - Throws: ``AgentRunFailure/bodyRenderFailed(_:)``,
    ///   ``AgentRunFailure/skillRenderFailed(skill:description:)``,
    ///   ``AgentRunFailure/agentsMdUnreadable(_:)``, or
    ///   ``AgentRunFailure/toolsFailed(_:)``.
    func makeSession(
        for request: AgentRunRequest, family: ParentRun.Family
    ) async throws(AgentRunFailure) -> Made {
        let definition = request.definition
        let body = try renderer.render(definition, prompt: request.prompt)
        let skillBodies = try await environment.skillsPreload.bodies(of: definition)
        let instructions = try instructions(parts: [body] + skillBodies)
        let slot = ModelMatch.match(
            definition.model, profile: environment.profile, inherited: request.inheritedSlot
        ).slot
        let tools = try await tools(
            for: request,
            as: ParentRun(depth: request.depth, slot: slot, agentID: definition.id, family: family))
        let model = ModelMatch.model(of: slot, in: environment.profile)
        let session = model.makeSession(
            configuration: SessionConfiguration(
                instructions: instructions,
                workingDirectory: environment.workingDirectory,
                tools: tools,
                compaction: CompactionSettings(
                    budget: environment.budget(model.contextTokens),
                    prompt: definition.compactionPrompt ?? .default),
                agentSpawn: request.agentSpawn,
                mailOnlyAnswerLimit: environment.mailOnlyAnswerLimit,
                inlineSettleGrace: environment.inlineSettleGrace))
        return Made(session: session, slot: slot)
    }

    /// Puts the instructions of a run in order: the text of each `AGENTS.md`
    /// file of the working directory, outermost first, then `parts`.
    ///
    /// - Parameter parts: The rendered body of the agent, then the rendered
    ///   bodies of its skills.
    /// - Returns: The instructions of the session.
    /// - Throws: ``AgentRunFailure/agentsMdUnreadable(_:)`` when a file is not
    ///   readable text.
    private func instructions(parts: [String]) throws(AgentRunFailure) -> String {
        let documents: [AgentsMd.Document]
        do {
            documents = try AgentsMd.documents(from: environment.workingDirectory)
        } catch {
            throw .agentsMdUnreadable(String(describing: error))
        }
        return (documents.map(\.text) + parts).joined(separator: Self.instructionsSeparator)
    }

    /// Makes the new tools of the run of `request`.
    ///
    /// The run skips each entry that matches no tool. `runner.catalog()`
    /// gives the warnings of those entries.
    ///
    /// - Parameters:
    ///   - request: The run.
    ///   - parent: The new run as the `agents` tool sees it.
    /// - Returns: The tools of the session.
    /// - Throws: ``AgentRunFailure/toolsFailed(_:)`` when the maker of the
    ///   `agents` tool throws.
    private func tools(
        for request: AgentRunRequest, as parent: ParentRun
    ) async throws(AgentRunFailure) -> [any Tool] {
        let definition = request.definition
        let agentsTool = agentsToolFactory(for: request, as: parent)
        do {
            return try await ToolResolver(agent: definition.id, provenance: definition.provenance)
                .resolve(
                    tools: definition.tools?.map(ToolSpec.parse),
                    disallowed: definition.disallowedTools.map(ToolSpec.parse),
                    catalog: environment.tools,
                    agentsTool: agentsTool
                ).tools
        } catch {
            throw .toolsFailed(String(describing: error))
        }
    }

    /// Gives the maker of the `agents` tool of the run of `request`.
    ///
    /// The tool keeps the link to the caller of the run: the context of the
    /// call that started the run, and the session of that call. A
    /// host-started run has no context, thus its tool has no link.
    /// ``mountedGrant(for:belowMaxDepth:hasCaller:)`` gives the grant of the
    /// tool.
    ///
    /// A host-started run at ``AgentEnvironment/maxDepth`` gets no maker:
    /// each run that it starts would be deeper than the limit, and it has no
    /// caller to send a message to. An `Agent` entry of its `tools` key then
    /// matches no tool, and the run skips it.
    ///
    /// - Parameters:
    ///   - request: The run.
    ///   - parent: The new run as the `agents` tool sees it.
    /// - Returns: The maker, or `nil` when the run gets no `agents` tool.
    private func agentsToolFactory(
        for request: AgentRunRequest, as parent: ParentRun
    ) -> ToolResolver.AgentsToolFactory? {
        let belowMaxDepth = request.depth < environment.maxDepth
        let callerLink = request.context.map { call in
            AgentsToolContext.CallerLink(call: call, sessionID: call.sessionID)
        }
        guard let maker = request.agentsTool, belowMaxDepth || callerLink != nil else {
            return nil
        }
        return { entryGrant in
            guard let grant = Self.mountedGrant(
                for: entryGrant, belowMaxDepth: belowMaxDepth, hasCaller: callerLink != nil)
            else {
                return nil
            }
            return try await maker(parent, callerLink, grant, entryGrant?.allowedNames)
        }
    }

    /// Gives the grant of the `agents` tool of one run.
    ///
    /// | Case | Grant |
    /// |---|---|
    /// | an `Agent` entry, below `maxDepth` | ``AgentsToolContext/Grant/full`` |
    /// | an `Agent` entry at `maxDepth`, with a caller | ``AgentsToolContext/Grant/messagingOnly`` |
    /// | no `Agent` entry, with a caller | ``AgentsToolContext/Grant/messagingOnly`` |
    /// | each other case | no tool |
    ///
    /// A `disallowedTools` entry that denies the tool wins over this table:
    /// the resolver then does not ask for a grant.
    ///
    /// - Parameters:
    ///   - entryGrant: The grant of the `Agent` entries of `tools`, or `nil`
    ///     when no entry grants the tool.
    ///   - belowMaxDepth: `true` when the depth of the run is less than
    ///     ``AgentEnvironment/maxDepth``.
    ///   - hasCaller: `true` when a tool call started the run.
    /// - Returns: The grant, or `nil` when the run gets no `agents` tool.
    private static func mountedGrant(
        for entryGrant: AgentsGrant?, belowMaxDepth: Bool, hasCaller: Bool
    ) -> AgentsToolContext.Grant? {
        if entryGrant != nil && belowMaxDepth {
            return .full
        }
        return hasCaller ? .messagingOnly : nil
    }
}
