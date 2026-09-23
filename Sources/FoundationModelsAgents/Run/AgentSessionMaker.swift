import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter

/// Makes the session of one agent run: plan.md §8 steps 2 to 5.
///
/// 2. Render the body with the prompt as `$ARGUMENTS`.
/// 3. Put the instructions in order: the `AGENTS.md` files of the working
///    directory, outermost first, then the rendered body.
/// 4. Resolve the tools.
/// 5. Match the model, and make the session on the slot of the match.
///
/// Each step that fails stops the run before it makes a session.
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
    /// - Parameter request: The run to make the session for.
    /// - Returns: The new session and its slot.
    /// - Throws: ``AgentRunFailure/bodyRenderFailed(_:)``,
    ///   ``AgentRunFailure/agentsMdUnreadable(_:)``, or
    ///   ``AgentRunFailure/toolsFailed(_:)``.
    func makeSession(for request: AgentRunRequest) async throws(AgentRunFailure) -> Made {
        let definition = request.definition
        let instructions = try instructions(
            body: renderer.render(definition, prompt: request.prompt))
        let tools = try await tools(for: request)
        let slot = ModelMatch.match(
            definition.model, profile: environment.profile, inherited: request.inheritedSlot
        ).slot
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
    /// file of the working directory, outermost first, then `body`.
    ///
    /// - Parameter body: The rendered body of the agent.
    /// - Returns: The instructions of the session.
    /// - Throws: ``AgentRunFailure/agentsMdUnreadable(_:)`` when a file is not
    ///   readable text.
    private func instructions(body: String) throws(AgentRunFailure) -> String {
        let documents: [AgentsMd.Document]
        do {
            documents = try AgentsMd.documents(from: environment.workingDirectory)
        } catch {
            throw .agentsMdUnreadable(String(describing: error))
        }
        return (documents.map(\.text) + [body]).joined(separator: Self.instructionsSeparator)
    }

    /// Makes the new tools of the run of `request` (plan.md §5).
    ///
    /// The run skips each entry that matches no tool. `runner.catalog()`
    /// gives the warnings of those entries.
    ///
    /// - Parameter request: The run.
    /// - Returns: The tools of the session.
    /// - Throws: ``AgentRunFailure/toolsFailed(_:)`` when the factory of the
    ///   `agents` tool throws.
    private func tools(for request: AgentRunRequest) async throws(AgentRunFailure) -> [any Tool] {
        let definition = request.definition
        do {
            return try await ToolResolver(agent: definition.id, provenance: definition.provenance)
                .resolve(
                    tools: definition.tools?.map(ToolSpec.parse),
                    disallowed: definition.disallowedTools.map(ToolSpec.parse),
                    catalog: environment.tools,
                    agentsTool: request.agentsTool
                ).tools
        } catch {
            throw .toolsFailed(String(describing: error))
        }
    }
}
