import FoundationModels

/// Resolves the `tools` and `disallowedTools` entries of one agent to new
/// tool instances, with the Claude semantics.
///
/// The resolver holds the agent and the file that its diagnostics are
/// about. ``AgentToolSelection`` applies the rules, and it is the same code
/// path as ``AgentDefinition/toolSelection(over:hasAgentsTool:)``.
struct ToolResolver: Sendable {
    /// Makes the `agents` tool. It gets the grant of the `Agent` entries of
    /// `tools`, or `nil` when no entry grants the tool. It gives `nil` when
    /// the run gets no `agents` tool for that grant. It is `async throws`,
    /// because `AgentsTool.make(context:)` is `async throws`.
    typealias AgentsToolFactory = @Sendable (AgentsGrant?) async throws -> (any Tool)?

    /// The warning of an `Agent` entry when each run of the agent is at
    /// ``AgentEnvironment/maxDepth``.
    ///
    /// The text tells both cases: a run with a caller gets the messaging
    /// tool, and a host-started run gets no `agents` tool.
    static let maxDepthAgentEntryMessage = """
        each run of this agent is at maxDepth, thus its 'Agent' entry cannot start agents: \
        a run with a caller gets only the message ops (send caller, send agent), \
        and a host-started run gets no agents tool
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
    ///     ``AgentEnvironment/maxDepth``. An `Agent` entry then gives a run
    ///     with a caller only the message ops, and a host-started run no
    ///     `agents` tool. The agent gets a warning.
    /// - Returns: The warnings, in order.
    static func diagnostics(
        of definition: AgentDefinition, catalog: ToolCatalog, hasAgentsTool: Bool, atMaxDepth: Bool
    ) -> [AgentDiagnostic] {
        let selection = selection(of: definition, catalog: catalog, hasAgentsTool: hasAgentsTool)
        return selection.diagnostics
            + ToolResolver(agent: definition.id, provenance: definition.provenance)
                .maxDepthDiagnostics(of: selection, atMaxDepth: atMaxDepth)
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
    /// Each kept tool of the catalog (``ToolCatalog/registerKept(_:vocabulary:_:)``)
    /// is in the result, whatever the entries are: its factory gets
    /// `definition` one time. Its names, and its capability names, are known
    /// names, thus an entry that matches only them is not a warning.
    ///
    /// - Parameters:
    ///   - definition: The agent of the run. Its `tools` and
    ///     `disallowedTools` keys give the entries.
    ///   - catalog: The tool catalog. Each selected factory, and each kept
    ///     factory, is called one time.
    ///   - agentsTool: Makes the `agents` tool, or `nil` when the run cannot
    ///     get one.
    /// - Returns: The new tools, the catalog tools in name order, then the
    ///   kept tools in name order, then the `agents` tool, and the warnings.
    /// - Throws: The error of `agentsTool`.
    func resolve(
        _ definition: AgentDefinition,
        catalog: ToolCatalog,
        agentsTool: AgentsToolFactory?
    ) async throws -> (tools: [any Tool], diagnostics: [AgentDiagnostic]) {
        let selection = Self.selection(of: definition, catalog: catalog, hasAgentsTool: agentsTool != nil)
        let catalogTools = selection.names.compactMap(catalog.makeTool(named:))
            + catalog.makeKeptTools(for: definition)
        guard let agentsTool, !selection.deniesAgents,
              let mountedTool = try await agentsTool(selection.agentsGrant)
        else {
            return (catalogTools, selection.diagnostics)
        }
        return (catalogTools + [mountedTool], selection.diagnostics)
    }


    /// Applies the rules to the entries of `definition` over the names of
    /// `catalog`, its kept names included. ``diagnostics(of:catalog:hasAgentsTool:atMaxDepth:)``
    /// and ``resolve(_:catalog:agentsTool:)`` share this step.
    ///
    /// - Parameters:
    ///   - definition: The agent.
    ///   - catalog: The tool catalog.
    ///   - hasAgentsTool: `true` when the resolution has an `agents` tool
    ///     factory.
    /// - Returns: The selection, with the diagnostics of the agent.
    private static func selection(
        of definition: AgentDefinition, catalog: ToolCatalog, hasAgentsTool: Bool
    ) -> AgentToolSelection {
        definition.toolSelection(vocabulary: ToolVocabulary(catalog: catalog, hasAgentsTool: hasAgentsTool))
    }

    /// Gives the maxDepth warning of one selection.
    ///
    /// - Parameters:
    ///   - selection: The selection.
    ///   - atMaxDepth: `true` when each run of the agent is at
    ///     ``AgentEnvironment/maxDepth``.
    /// - Returns: One warning when the selection grants the `agents` tool and
    ///   each run is at `maxDepth`, otherwise none.
    private func maxDepthDiagnostics(of selection: AgentToolSelection, atMaxDepth: Bool) -> [AgentDiagnostic] {
        guard atMaxDepth, selection.agentsGrant != nil else {
            return []
        }
        return [
            AgentFinding(code: .agentEntryAtMaxDepth, severity: .warning, message: Self.maxDepthAgentEntryMessage)
                .diagnostic(agent: agent, provenance: provenance)
        ]
    }
}
