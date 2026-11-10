/// The tools that a run of one agent gets, before a tool is made.
///
/// ``AgentDefinition/toolSelection(over:hasAgentsTool:)`` gives this value.
/// A run applies the same rules to the same lists, thus a host can read the
/// `tools` and `disallowedTools` keys of an agent as a run reads them.
///
/// `disallowedTools` applies first, then `tools`. No `tools` key selects
/// each name, and no grant of the `agents` tool: only an explicit `tools`
/// entry gives a grant. An entry that matches no tool gives a warning.
public struct AgentToolSelection: Sendable, Equatable {
    /// The selected names, in sorted order.
    public let names: [String]

    /// The grant of the `agents` tool, or `nil` when the selection does not
    /// hold it.
    public let agentsGrant: AgentsGrant?

    /// `true` when a `disallowedTools` entry denies the `agents` tool. An
    /// explicit deny wins: the run then gets no `agents` tool of any grant,
    /// and ``agentsGrant`` is `nil`.
    public let deniesAgents: Bool

    /// The warnings, with the id and the provenance of the agent: first the
    /// `disallowedTools` entries, then the `tools` entries, each in entry
    /// order.
    public let diagnostics: [AgentDiagnostic]

    /// Applies the resolution rules to the entries of one agent.
    ///
    /// - Parameters:
    ///   - tools: The `tools` entries, or `nil` when the key is absent.
    ///   - disallowed: The `disallowedTools` entries.
    ///   - vocabulary: The known tool names.
    ///   - agent: The id of the agent, or `nil` when it is not known.
    ///   - provenance: The file that the diagnostics are about.
    init(
        tools: [ToolSpec]?,
        disallowed: [ToolSpec],
        vocabulary: ToolVocabulary,
        agent: String?,
        provenance: AgentDiagnostic.Provenance
    ) {
        let selection = ToolSelection(tools: tools, disallowed: disallowed, vocabulary: vocabulary)
        self.names = selection.names
        self.agentsGrant = selection.agentsGrant
        self.deniesAgents = selection.deniesAgents
        self.diagnostics = selection.findings.map { finding in
            finding.diagnostic(agent: agent, provenance: provenance)
        }
    }
}

extension AgentDefinition {
    /// Gives the tools that a run of this agent gets from `names`.
    ///
    /// The selection uses the rules of a run, and it makes no tool. The
    /// entries match the names as follows:
    ///
    /// - A plain entry matches a name of `names` exactly, for example
    ///   `files`, `shell`, or `skills`.
    /// - The entries `agents`, `Agent`, and `Agent(a, b)` give
    ///   ``AgentToolSelection/agentsGrant`` only when `hasAgentsTool` is
    ///   `true`. They never put `agents` into
    ///   ``AgentToolSelection/names``: with `hasAgentsTool` set to `true`, the
    ///   selection removes the name `agents` from `names`, because the
    ///   `agents` tool does not come from the catalog. With `hasAgentsTool`
    ///   set to `false`, `Agent` and `Agent(a, b)` match no tool and give a
    ///   warning.
    /// - The MCP entry `mcp__<server>`, or `mcp__<server>__*`, matches each
    ///   name `mcp__<server>__<tool>` of `names`. It does not match a tool of
    ///   a server whose name only starts with `<server>`.
    /// - The MCP entry for all servers, `mcp__*`, matches each name of
    ///   `names` that starts with `mcp__`.
    ///
    /// Thus give each MCP tool in `names` as `mcp__<server>__<tool>`.
    ///
    /// - Parameters:
    ///   - names: The tool names that a run can get, in any order.
    ///   - hasAgentsTool: `true` when a run can get the `agents` tool.
    /// - Returns: The selection, with the diagnostics of this agent.
    public func toolSelection(over names: [String], hasAgentsTool: Bool) -> AgentToolSelection {
        AgentToolSelection(
            tools: tools?.map(ToolSpec.parse),
            disallowed: disallowedTools.map(ToolSpec.parse),
            vocabulary: ToolVocabulary(catalogNames: names, hasAgentsTool: hasAgentsTool),
            agent: id,
            provenance: provenance)
    }
}
