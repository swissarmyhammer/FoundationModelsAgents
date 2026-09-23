import FoundationModels

// The run start and `runner.catalog()` of later tasks call this type.
// periphery:ignore
/// Resolves the `tools` and `disallowedTools` entries of one agent to new
/// tool instances, with the Claude semantics of plan.md §5.
///
/// The resolver holds the agent and the file that its diagnostics are
/// about. `ToolSelection` holds the rules.
struct ToolResolver: Sendable {
    /// Makes the `agents` tool. It gets the agent names that the tool can
    /// start, or `nil` for all agents. It is `async throws`, because
    /// `AgentsTool.make(context:)` is `async throws`.
    typealias AgentsToolFactory = @Sendable ([String]?) async throws -> any Tool

    /// The id of the agent, or `nil` when it is not known.
    let agent: String?

    /// The file that the diagnostics are about.
    let provenance: AgentDiagnostic.Provenance

    /// Gives the tool warnings of one definition, and makes no tool.
    ///
    /// `runner.catalog()` adds these warnings to the diagnostics of the
    /// catalog. The warnings of `disallowedTools` come first.
    ///
    /// - Parameters:
    ///   - definition: The agent.
    ///   - catalog: The tool catalog of the runner.
    ///   - hasAgentsTool: `true` when the runner gives the `agents` tool.
    /// - Returns: The warnings, in order.
    static func diagnostics(
        of definition: AgentDefinition, catalog: ToolCatalog, hasAgentsTool: Bool
    ) -> [AgentDiagnostic] {
        let selection = ToolSelection(
            tools: definition.tools?.map(ToolSpec.parse),
            disallowed: definition.disallowedTools.map(ToolSpec.parse),
            vocabulary: ToolVocabulary(catalogNames: catalog.names, hasAgentsTool: hasAgentsTool))
        return ToolResolver(agent: definition.id, provenance: definition.provenance).diagnostics(of: selection)
    }

    /// Resolves the entries to new tool instances.
    ///
    /// No `tools` key gives the full catalog. `disallowed` applies first,
    /// then `tools`. The MCP patterns match by prefix. An entry that matches
    /// no tool is a warning and is skipped, and the warnings of `disallowed`
    /// come first. `Agent` and `Agent(a, b)` give the `agents` tool through
    /// `agentsTool`; with no `agentsTool`, they are unknown names.
    ///
    /// - Parameters:
    ///   - tools: The `tools` entries, or `nil` when the key is absent.
    ///   - disallowed: The `disallowedTools` entries.
    ///   - catalog: The tool catalog. Each selected factory is called one
    ///     time.
    ///   - agentsTool: Makes the `agents` tool, or `nil` when the run cannot
    ///     start agents.
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
        guard let agentsTool, let grant = selection.agentsGrant else {
            return (catalogTools, diagnostics)
        }
        return (catalogTools + [try await agentsTool(grant.allowedNames)], diagnostics)
    }

    /// Gives the diagnostics of the warnings of one selection.
    ///
    /// - Parameter selection: The selection.
    /// - Returns: One diagnostic for each finding, in order.
    private func diagnostics(of selection: ToolSelection) -> [AgentDiagnostic] {
        selection.findings.map { finding in finding.diagnostic(agent: agent, provenance: provenance) }
    }
}
