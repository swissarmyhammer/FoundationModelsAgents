import FoundationModels

/// Resolves the `tools` and `disallowedTools` entries of one agent to new
/// tool instances, with the Claude semantics of plan.md §5.
///
/// The resolver holds the agent and the file that its diagnostics are
/// about. `ToolSelection` holds the rules.
struct ToolResolver: Sendable {
    /// Makes the `agents` tool. It gets the grant of the `Agent` entries of
    /// `tools`, or `nil` when no entry grants the tool. It gives `nil` when
    /// the run gets no `agents` tool for that grant. It is `async throws`,
    /// because `AgentsTool.make(context:)` is `async throws`.
    typealias AgentsToolFactory = @Sendable (AgentsGrant?) async throws -> (any Tool)?

    /// The warning of an `Agent` entry when each run of the agent is at
    /// ``AgentEnvironment/maxDepth``.
    static let maxDepthAgentEntryMessage = """
        each run of this agent is at maxDepth, thus its 'Agent' entry gives only the message ops \
        (send caller, send agent); the run cannot start agents
        """

    /// The id of the agent, or `nil` when it is not known.
    let agent: String?

    /// The file that the diagnostics are about.
    let provenance: AgentDiagnostic.Provenance

    /// Gives the tool warnings of one definition, and makes no tool.
    ///
    /// `runner.catalog()` adds these warnings to the diagnostics of the
    /// catalog. The warnings of `disallowedTools` come first. The maxDepth
    /// warning comes last.
    ///
    /// - Parameters:
    ///   - definition: The agent.
    ///   - catalog: The tool catalog of the runner.
    ///   - hasAgentsTool: `true` when the runner can make the `agents` tool
    ///     for a run whose `tools` key lists it.
    ///   - atMaxDepth: `true` when each run of the agent is at
    ///     ``AgentEnvironment/maxDepth``. An `Agent` entry then gives only
    ///     the message ops, and the agent gets a warning.
    /// - Returns: The warnings, in order.
    static func diagnostics(
        of definition: AgentDefinition, catalog: ToolCatalog, hasAgentsTool: Bool, atMaxDepth: Bool
    ) -> [AgentDiagnostic] {
        let selection = ToolSelection(
            tools: definition.tools?.map(ToolSpec.parse),
            disallowed: definition.disallowedTools.map(ToolSpec.parse),
            vocabulary: ToolVocabulary(catalogNames: catalog.names, hasAgentsTool: hasAgentsTool))
        let resolver = ToolResolver(agent: definition.id, provenance: definition.provenance)
        return resolver.diagnostics(of: selection)
            + resolver.maxDepthDiagnostics(of: selection, atMaxDepth: atMaxDepth)
    }

    /// Resolves the entries to new tool instances.
    ///
    /// No `tools` key gives the full catalog. `disallowed` applies first,
    /// then `tools`. The MCP patterns match by prefix. An entry that matches
    /// no tool is a warning and is skipped, and the warnings of `disallowed`
    /// come first. The `tools` entries `Agent`, `Agent(a, b)`, and `agents`
    /// give a grant to `agentsTool`; with no `agentsTool`, they are unknown
    /// names. With no such entry, `agentsTool` gets `nil`, and it can give
    /// a tool all the same (the messaging tool of a run with a caller). An
    /// `Agent` entry of `disallowed` denies the tool of each grant, and
    /// then the resolver does not call `agentsTool`.
    ///
    /// - Parameters:
    ///   - tools: The `tools` entries, or `nil` when the key is absent.
    ///   - disallowed: The `disallowedTools` entries.
    ///   - catalog: The tool catalog. Each selected factory is called one
    ///     time.
    ///   - agentsTool: Makes the `agents` tool, or `nil` when the run cannot
    ///     get one.
    /// - Returns: The new tools, the catalog tools in name order and then the
    ///   `agents` tool, and the warnings.
    /// - Throws: The error of `agentsTool`.
    func resolve(
        tools: [ToolSpec]?,
        disallowed: [ToolSpec],
        catalog: ToolCatalog,
        agentsTool: AgentsToolFactory?
    ) async throws -> (tools: [any Tool], diagnostics: [AgentDiagnostic]) {
        let selection = ToolSelection(
            tools: tools,
            disallowed: disallowed,
            vocabulary: ToolVocabulary(catalogNames: catalog.names, hasAgentsTool: agentsTool != nil))
        let catalogTools = selection.names.compactMap(catalog.makeTool(named:))
        let diagnostics = diagnostics(of: selection)
        guard let agentsTool, !selection.deniesAgents,
              let mountedTool = try await agentsTool(selection.agentsGrant)
        else {
            return (catalogTools, diagnostics)
        }
        return (catalogTools + [mountedTool], diagnostics)
    }

    /// Gives the diagnostics of the warnings of one selection.
    ///
    /// - Parameter selection: The selection.
    /// - Returns: One diagnostic for each finding, in order.
    private func diagnostics(of selection: ToolSelection) -> [AgentDiagnostic] {
        selection.findings.map { finding in finding.diagnostic(agent: agent, provenance: provenance) }
    }

    /// Gives the maxDepth warning of one selection.
    ///
    /// - Parameters:
    ///   - selection: The selection.
    ///   - atMaxDepth: `true` when each run of the agent is at
    ///     ``AgentEnvironment/maxDepth``.
    /// - Returns: One warning when the selection grants the `agents` tool and
    ///   each run is at `maxDepth`, otherwise none.
    private func maxDepthDiagnostics(of selection: ToolSelection, atMaxDepth: Bool) -> [AgentDiagnostic] {
        guard atMaxDepth, selection.agentsGrant != nil else {
            return []
        }
        return [
            AgentFinding(severity: .warning, message: Self.maxDepthAgentEntryMessage)
                .diagnostic(agent: agent, provenance: provenance)
        ]
    }
}
