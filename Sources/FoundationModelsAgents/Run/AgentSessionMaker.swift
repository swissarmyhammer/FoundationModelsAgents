import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter

/// Makes the session of one agent run: plan.md §8 steps 2 to 5.
///
/// 2. Render the body with the prompt as `$ARGUMENTS`.
/// 3. Put the instructions in order: the `AGENTS.md` files of the working
///    directory, outermost first, then the rendered body, then the rendered
///    body of each skill of the `skills` key, in the order of the key
///    (``AgentSkillsPreload``).
/// 4. Resolve the tools.
/// 5. Match the model, and make the session on the slot of the match.
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
    ///   - children: The list of the runs that the new run starts. The
    ///     `agents` tool of the run adds to it.
    /// - Returns: The new session and its slot.
    /// - Throws: ``AgentRunFailure/bodyRenderFailed(_:)``,
    ///   ``AgentRunFailure/skillRenderFailed(skill:description:)``,
    ///   ``AgentRunFailure/agentsMdUnreadable(_:)``, or
    ///   ``AgentRunFailure/toolsFailed(_:)``.
    func makeSession(
        for request: AgentRunRequest, children: AgentRunChildren
    ) async throws(AgentRunFailure) -> Made {
        let definition = request.definition
        let body = try renderer.render(definition, prompt: request.prompt)
        let skillBodies = try await AgentSkillsPreload(skills: environment.skills).bodies(of: definition)
        let instructions = try instructions(parts: [body] + skillBodies)
        let slot = ModelMatch.match(
            definition.model, profile: environment.profile, inherited: request.inheritedSlot
        ).slot
        let tools = try await tools(
            for: request, as: ParentRun(depth: request.depth, slot: slot, children: children))
        let model = ModelMatch.model(of: slot, in: environment.profile)
        let session = model.makeSession(
            instructions: instructions,
            workingDirectory: environment.workingDirectory,
            tools: tools,
            budget: environment.budget(model.contextTokens),
            compactionPrompt: definition.compactionPrompt ?? .default,
            agentSpawn: request.agentSpawn)
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

    /// Makes the new tools of the run of `request` (plan.md §5).
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
        let agentsTool = request.agentsTool.map { maker -> ToolResolver.AgentsToolFactory in
            { allowedNames in try await maker(parent, allowedNames) }
        }
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
}
