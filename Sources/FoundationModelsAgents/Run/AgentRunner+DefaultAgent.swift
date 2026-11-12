import FoundationModelsExtras

/// The instructions of one agent, for a session that the host makes with no
/// run: its main session.
///
/// ``text`` is the rendered body, then the rendered body of each skill of the
/// `skills:` key, in the order of the key, joined as a run joins them. It
/// holds no `AGENTS.md` text and no preamble
/// (``AgentEnvironment/instructionsPreamble``): the host adds its own.
public struct SessionAgentInstructions: Sendable {
    /// The agent of the session: a definition of the catalog, or of
    /// ``AgentRegistry/rootAgent(in:id:)``.
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
    /// Gives the instructions of an agent, for the main session of the host.
    ///
    /// The host makes its main session from these instructions with no run.
    /// The body renders as the body of a run does, with the variables and
    /// the template context of the registry, and `$ARGUMENTS` as empty text:
    /// the session has no prompt yet. The partials of the render come from
    /// the provenance of `definition` and its document kind, not from the
    /// catalog. Thus a definition that the catalog does not hold renders,
    /// for example the result of ``AgentRegistry/rootAgent(in:id:)`` for a
    /// folder that no layer of the registry holds. The `skills:` preload
    /// uses the skills registry and the visibility rule of the environment,
    /// as a run does.
    ///
    /// The instructions do not hold the preamble of the environment
    /// (``AgentEnvironment/instructionsPreamble``). The host adds the
    /// preamble to its main session itself, thus the text occurs one time.
    ///
    /// The call is ``sessionAgentInstructions(for:templateContext:)`` with
    /// the template context of the registry.
    ///
    /// - Parameter definition: The agent of the session.
    /// - Returns: The instructions.
    /// - Throws: ``AgentRunFailure/bodyRenderFailed(_:)`` or
    ///   ``AgentRunFailure/skillRenderFailed(skill:description:)``.
    public nonisolated func sessionAgentInstructions(
        for definition: AgentDefinition
    ) async throws(AgentRunFailure) -> SessionAgentInstructions {
        try await sessionAgentInstructions(for: definition, templateContext: registry.templateContext)
    }

    /// Gives the instructions of an agent, for the main session of the host,
    /// with a template context of the host.
    ///
    /// The instructions are those of ``sessionAgentInstructions(for:)``, but
    /// the body of the agent, and each partial of the body, renders with
    /// `templateContext` in place of the template context of the registry.
    /// Thus a host gives the values of the tool selection of the agent, and a
    /// body that reads `tools.<group>.enabled` sees the tools that the model
    /// of the session has. The `agents` group is off for an agent that
    /// denies the `agents` tool, as for the context of the registry.
    ///
    /// The layers, the variables, and the `skills:` preload do not change.
    ///
    /// - Parameters:
    ///   - definition: The agent of the session.
    ///   - templateContext: The template context of the render of the body.
    /// - Returns: The instructions.
    /// - Throws: ``AgentRunFailure/bodyRenderFailed(_:)`` or
    ///   ``AgentRunFailure/skillRenderFailed(skill:description:)``.
    public nonisolated func sessionAgentInstructions(
        for definition: AgentDefinition, templateContext: [String: TemplateValue]
    ) async throws(AgentRunFailure) -> SessionAgentInstructions {
        let preload = environment.skillsPreload
        return SessionAgentInstructions(
            definition: definition,
            body: try renderer.render(definition, prompt: "", templateContext: templateContext),
            skillBodies: try await preload.bodies(of: definition),
            diagnostics: preload.diagnostics(of: definition))
    }

    /// Gives the instructions of the default agent of the current catalog,
    /// for the main session of the host.
    ///
    /// The instructions are those of ``sessionAgentInstructions(for:)`` for
    /// the default agent. Thus they do not hold the preamble of the
    /// environment (``AgentEnvironment/instructionsPreamble``): the host adds
    /// it to its main session itself.
    ///
    /// The default agent is never model-visible, thus the main session cannot
    /// start it with the `agents` tool.
    ///
    /// - Returns: The instructions, or `nil` when no layer gives the default
    ///   agent. The host then uses its own instructions.
    /// - Throws: ``AgentRunFailure/bodyRenderFailed(_:)`` or
    ///   ``AgentRunFailure/skillRenderFailed(skill:description:)``.
    public nonisolated func defaultAgentInstructions() async throws(AgentRunFailure) -> SessionAgentInstructions? {
        guard let definition = registry.catalog().defaultAgent else { return nil }
        return try await sessionAgentInstructions(for: definition)
    }
}
