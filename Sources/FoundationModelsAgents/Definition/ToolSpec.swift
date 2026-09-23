import Foundation

/// One entry of the `tools` or `disallowedTools` key, as a typed value
/// (plan.md §5).
///
/// The parse does not look up a tool. The tool resolution matches each value
/// to the tool catalog and makes a warning for an unknown name.
enum ToolSpec: Sendable, Equatable {
    /// One tool, by its name. An entry that has no other form gives this
    /// value.
    case name(String)

    /// All the tools of one MCP server. The value is the prefix of their
    /// names, for example `mcp__srv`.
    case mcpPrefix(String)

    /// All the MCP tools of all servers.
    case mcpAll

    /// The `agents` tool. `allowed` is `nil` when the entry is `Agent` alone,
    /// thus all agents are allowed. Otherwise it holds the agent names in
    /// parentheses, in their order.
    case agent(allowed: [String]?)

    /// The entry that gives the `agents` tool.
    private static let agentEntry = "Agent"

    /// The text in front of the allowed agent names.
    private static let agentListOpening = agentEntry + "("

    /// The text after the allowed agent names.
    private static let agentListClosing = ")"

    /// The text in front of each MCP tool name.
    private static let mcpMarker = "mcp__"

    /// The text between the server and the tool in an MCP tool name.
    private static let mcpSeparator = "__"

    /// The wildcard of the MCP patterns.
    private static let wildcard = "*"

    /// The separator between two names of an `Agent(...)` entry.
    private static let agentNameSeparator = ", "

    /// The entry text of this value, as the frontmatter can write it.
    ///
    /// `parse(_:)` of the text gives this value again. The diagnostics of the
    /// tool resolution quote it.
    var entry: String {
        switch self {
        case .name(let name):
            name
        case .mcpPrefix(let prefix):
            prefix
        case .mcpAll:
            Self.mcpMarker + Self.wildcard
        case .agent(let allowed):
            allowed.map { names in
                Self.agentListOpening + names.joined(separator: Self.agentNameSeparator) + Self.agentListClosing
            } ?? Self.agentEntry
        }
    }

    /// Tells if this MCP pattern matches one tool name.
    ///
    /// `mcpPrefix("mcp__srv")` matches each name that starts with
    /// `mcp__srv__`, thus it does not match a tool of the server `srvx`.
    /// `mcpAll` matches each name that starts with `mcp__`. A value that is
    /// not an MCP pattern matches no name.
    ///
    /// - Parameter toolName: The name of one catalog tool.
    /// - Returns: `true` when the pattern matches the name.
    func matchesMCPTool(named toolName: String) -> Bool {
        switch self {
        case .mcpPrefix(let prefix):
            toolName.hasPrefix(prefix + Self.mcpSeparator)
        case .mcpAll:
            toolName.hasPrefix(Self.mcpMarker)
        case .name, .agent:
            false
        }
    }

    /// Parses one entry of `tools` or `disallowedTools`.
    ///
    /// - `Agent` gives `agent(allowed: nil)`. `Agent(a, b)` gives
    ///   `agent(allowed: ["a", "b"])`, with each name trimmed, and `Agent()`
    ///   gives `agent(allowed: [])`.
    /// - `mcp__srv` and `mcp__srv__*` give `mcpPrefix("mcp__srv")`. `mcp__*`
    ///   gives `mcpAll`.
    /// - Other text gives `name`, with the white space at the two ends
    ///   removed.
    ///
    /// - Parameter entry: The entry as the frontmatter writes it.
    /// - Returns: The typed value of the entry.
    static func parse(_ entry: String) -> ToolSpec {
        let text = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        return agent(in: text) ?? mcpPattern(in: text) ?? .name(text)
    }

    /// Parses the `Agent` forms.
    ///
    /// - Parameter text: The trimmed entry.
    /// - Returns: The `agent` value, or `nil` when `text` is not an `Agent`
    ///   form.
    private static func agent(in text: String) -> ToolSpec? {
        if text == agentEntry {
            return .agent(allowed: nil)
        }
        guard text.hasPrefix(agentListOpening), text.hasSuffix(agentListClosing) else {
            return nil
        }
        let names = text.dropFirst(agentListOpening.count).dropLast(agentListClosing.count)
        return .agent(allowed: AgentFrontmatterReader.entries(inCommaSeparated: String(names)))
    }

    /// Parses the MCP patterns.
    ///
    /// - Parameter text: The trimmed entry.
    /// - Returns: `mcpAll` or `mcpPrefix`, or `nil` when `text` is not an MCP
    ///   pattern. The name of one MCP tool, for example `mcp__srv__tool`, is
    ///   not a pattern.
    private static func mcpPattern(in text: String) -> ToolSpec? {
        guard text.hasPrefix(mcpMarker) else {
            return nil
        }
        if text == mcpMarker + wildcard {
            return .mcpAll
        }
        let serverWildcard = mcpSeparator + wildcard
        let prefix = text.hasSuffix(serverWildcard) ? String(text.dropLast(serverWildcard.count)) : text
        let server = prefix.dropFirst(mcpMarker.count)
        guard !server.isEmpty, !server.contains(mcpSeparator), !server.contains(wildcard) else {
            return nil
        }
        return .mcpPrefix(prefix)
    }
}
