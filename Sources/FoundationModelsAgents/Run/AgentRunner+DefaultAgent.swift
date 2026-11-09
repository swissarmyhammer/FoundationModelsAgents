/// The instructions of the default agent, for a session that the host makes
/// with no run: its main session.
///
/// ``text`` is the rendered body, then the rendered body of each skill of the
/// `skills:` key, in the order of the key, joined as a run joins them. It
/// holds no `AGENTS.md` text: the host adds its own.
public struct DefaultAgentInstructions: Sendable {
    /// The default agent: the definition of the highest layer that gives it.
    public let definition: AgentDefinition

    /// The rendered body of the agent.
    public let body: String

    /// The rendered body of each skill of the `skills:` key that can load, in
    /// the order of the key.
    public let skillBodies: [String]

    /// One warning for each entry of the `skills:` key that does not load: a
    /// name that no skill has, or a skill that the `skills` tool hides.
    public let diagnostics: [AgentDiagnostic]

    /// The instructions of the session: ``body``, then ``skillBodies``.
    public var text: String {
        ([body] + skillBodies).joined(separator: AgentSessionMaker.instructionsSeparator)
    }
}

extension AgentRunner {
    /// Gives the instructions of the default agent of the current catalog,
    /// for the main session of the host.
    ///
    /// The host makes its main session from these instructions with no run.
    /// The body renders as the body of a run does, with the variables and
    /// the template context of the registry, and `$ARGUMENTS` as empty text:
    /// the session has no prompt yet. The `skills:` preload uses the skills
    /// registry and the visibility rule of the environment, as a run does.
    ///
    /// The default agent is never model-visible, thus the main session cannot
    /// start it with the `agents` tool.
    ///
    /// - Returns: The instructions, or `nil` when no layer gives the default
    ///   agent. The host then uses its own instructions.
    /// - Throws: ``AgentRunFailure/bodyRenderFailed(_:)`` or
    ///   ``AgentRunFailure/skillRenderFailed(skill:description:)``.
    public nonisolated func defaultAgentInstructions() async throws(AgentRunFailure) -> DefaultAgentInstructions? {
        guard let definition = registry.catalog().defaultAgent else { return nil }
        let preload = environment.skillsPreload
        return DefaultAgentInstructions(
            definition: definition,
            body: try renderer.render(definition, prompt: ""),
            skillBodies: try await preload.bodies(of: definition),
            diagnostics: preload.diagnostics(of: definition))
    }
}
