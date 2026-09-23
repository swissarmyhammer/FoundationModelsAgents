/// The grant of the `agents` tool: all agents, or only the named agents.
enum AgentsGrant: Sendable, Equatable {
    /// The tool can start each agent. The entry is `Agent` or `agents`.
    case all

    /// The tool can start only these agents, in their order. The entry is
    /// `Agent(a, b)`.
    case only([String])

    /// The agent names for the `agents` tool factory: `nil` for all agents.
    var allowedNames: [String]? {
        switch self {
        case .all:
            nil
        case .only(let names):
            names
        }
    }

    /// Makes the grant of one `Agent` entry.
    ///
    /// - Parameter allowed: The names in parentheses, or `nil` for `Agent`
    ///   alone.
    init(allowed: [String]?) {
        self = allowed.map(AgentsGrant.only) ?? .all
    }

    /// Joins this grant and a second grant.
    ///
    /// `all` with a different grant gives `all`. Two `only` grants give the
    /// names of the two, in order, with each name one time.
    ///
    /// - Parameter other: The second grant.
    /// - Returns: The joined grant.
    func merged(with other: AgentsGrant) -> AgentsGrant {
        guard case .only(let names) = self, case .only(let otherNames) = other else {
            return .all
        }
        return .only(names + otherNames.filter { !names.contains($0) })
    }
}

/// What one `tools` or `disallowedTools` entry matches.
struct ToolMatch: Sendable {
    /// The match of an entry that matches no tool.
    static let nothing = ToolMatch(names: [], agentsGrant: nil)

    /// The catalog names that the entry matches, in sorted order.
    let names: [String]

    /// The grant of the `agents` tool, or `nil` when the entry does not
    /// match the `agents` tool.
    let agentsGrant: AgentsGrant?

    /// `true` when the entry matches no tool. The resolution then gives a
    /// warning.
    var isEmpty: Bool {
        names.isEmpty && agentsGrant == nil
    }
}

/// The tool names that one resolution knows: the catalog names, and the
/// `agents` tool when a factory for it is present.
struct ToolVocabulary: Sendable {
    /// The name of the `agents` tool.
    static let agentsToolName = "agents"

    /// The catalog names, in sorted order. When the `agents` tool factory is
    /// present, the factory gives the `agents` tool, thus the catalog name
    /// `agents` is not here.
    let catalogNames: [String]

    /// `true` when the resolution has an `agents` tool factory.
    let hasAgentsTool: Bool

    /// The match of no `tools` key: each catalog name, and the `agents` tool
    /// with all agents when its factory is present.
    var everything: ToolMatch {
        ToolMatch(names: catalogNames, agentsGrant: hasAgentsTool ? .all : nil)
    }

    /// Makes the vocabulary of one resolution.
    ///
    /// - Parameters:
    ///   - catalogNames: The names of the tool catalog, in sorted order.
    ///   - hasAgentsTool: `true` when the resolution has an `agents` tool
    ///     factory.
    init(catalogNames: [String], hasAgentsTool: Bool) {
        self.catalogNames = hasAgentsTool ? catalogNames.filter { $0 != Self.agentsToolName } : catalogNames
        self.hasAgentsTool = hasAgentsTool
    }

    /// Matches one entry to the known names.
    ///
    /// - Parameter spec: The parsed entry.
    /// - Returns: The names and the `agents` grant that the entry matches.
    func match(_ spec: ToolSpec) -> ToolMatch {
        switch spec {
        case .name(let name):
            match(name: name)
        case .mcpPrefix, .mcpAll:
            ToolMatch(names: catalogNames.filter(spec.matchesMCPTool(named:)), agentsGrant: nil)
        case .agent(let allowed):
            hasAgentsTool ? ToolMatch(names: [], agentsGrant: AgentsGrant(allowed: allowed)) : .nothing
        }
    }

    /// Matches one plain tool name.
    ///
    /// - Parameter name: The name of the entry.
    /// - Returns: The `agents` tool with all agents for the name `agents`
    ///   when its factory is present, the name when the catalog holds it, or
    ///   `nothing`.
    private func match(name: String) -> ToolMatch {
        if hasAgentsTool, name == Self.agentsToolName {
            return ToolMatch(names: [], agentsGrant: .all)
        }
        return catalogNames.contains(name) ? ToolMatch(names: [name], agentsGrant: nil) : .nothing
    }
}

/// The key of a frontmatter tool list.
enum ToolListKey: String, Sendable {
    /// The `tools` key.
    case tools

    /// The `disallowedTools` key.
    case disallowedTools

    /// What the resolution does with an entry of this key that matches no
    /// tool.
    var unknownEntryOutcome: String {
        switch self {
        case .tools:
            "the entry is skipped"
        case .disallowedTools:
            "the entry denies nothing"
        }
    }

    /// The warning for one entry of this key that matches no tool.
    ///
    /// - Parameter spec: The entry.
    /// - Returns: The finding.
    func unknownEntryFinding(_ spec: ToolSpec) -> AgentFinding {
        AgentFinding(
            severity: .warning,
            message: "the '\(rawValue)' entry '\(spec.entry)' matches no tool of the catalog; \(unknownEntryOutcome)")
    }
}

/// The result of the tool resolution rules of plan.md §5, before a tool is
/// made.
///
/// `disallowedTools` applies first, then `tools`. No `tools` key selects
/// each known tool. A denied name that `tools` also names is removed with no
/// warning. An entry that matches no tool is a warning, and the warnings of
/// `disallowedTools` come first, because a dropped deny gives more access
/// than the author wanted.
struct ToolSelection: Sendable {
    /// The selected catalog names, in sorted order.
    let names: [String]

    /// The grant of the `agents` tool, or `nil` when the selection does not
    /// hold it.
    let agentsGrant: AgentsGrant?

    /// The warnings: first the `disallowedTools` entries, then the `tools`
    /// entries, each in entry order.
    let findings: [AgentFinding]

    /// Applies the resolution rules.
    ///
    /// An `Agent` entry in `disallowedTools`, with or without names, denies
    /// the whole `agents` tool.
    ///
    /// - Parameters:
    ///   - tools: The `tools` entries, or `nil` when the key is absent.
    ///   - disallowed: The `disallowedTools` entries.
    ///   - vocabulary: The known tool names.
    init(tools: [ToolSpec]?, disallowed: [ToolSpec], vocabulary: ToolVocabulary) {
        let denials = disallowed.map(vocabulary.match)
        let grants = tools.map { specs in specs.map(vocabulary.match) } ?? [vocabulary.everything]
        let deniesAgents = denials.contains { denial in denial.agentsGrant != nil }
        self.names = Set(grants.flatMap(\.names)).subtracting(denials.flatMap(\.names)).sorted()
        self.agentsGrant = deniesAgents ? nil : Self.joinedGrant(of: grants)
        self.findings = Self.unknownEntryFindings(disallowed, matches: denials, key: .disallowedTools)
            + Self.unknownEntryFindings(tools ?? [], matches: grants, key: .tools)
    }

    /// Joins the `agents` grants of the matches.
    ///
    /// - Parameter matches: The matches of the `tools` entries.
    /// - Returns: The joined grant, or `nil` when no match holds a grant.
    private static func joinedGrant(of matches: [ToolMatch]) -> AgentsGrant? {
        matches.compactMap(\.agentsGrant).reduce(nil) { joined, grant in
            joined?.merged(with: grant) ?? grant
        }
    }

    /// The warnings for the entries that match no tool.
    ///
    /// - Parameters:
    ///   - specs: The entries of one key.
    ///   - matches: The match of each entry, in the same order.
    ///   - key: The key of the entries.
    /// - Returns: One warning for each entry that matches no tool.
    private static func unknownEntryFindings(
        _ specs: [ToolSpec], matches: [ToolMatch], key: ToolListKey
    ) -> [AgentFinding] {
        zip(specs, matches)
            .filter { _, match in match.isEmpty }
            .map { spec, _ in key.unknownEntryFinding(spec) }
    }
}
