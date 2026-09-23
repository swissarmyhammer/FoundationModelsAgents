@testable import FoundationModelsAgents
import Testing

/// Pins `ToolSpec.parse(_:)` (plan.md §5).
///
/// Each row gives one entry of `tools` or `disallowedTools` and the value
/// that the parse must give for it.
@Suite("Tool spec")
struct ToolSpecTests {
    /// One entry and the value that the parse must give.
    struct Row: Sendable, CustomTestStringConvertible {
        /// The entry as the frontmatter writes it.
        let entry: String

        /// The value that the parse must give.
        let expected: ToolSpec

        /// The entry, as the name of the test case.
        var testDescription: String {
            "`\(entry)`"
        }
    }

    /// The entries of each form in plan.md §5, with their values.
    static let rows: [Row] = [
        Row(entry: "Read", expected: .name("Read")),
        Row(entry: "agents", expected: .name("agents")),
        Row(entry: "Agent", expected: .agent(allowed: nil)),
        Row(entry: "Agent(a, b)", expected: .agent(allowed: ["a", "b"])),
        Row(entry: "Agent(code-reviewer, test-writer)", expected: .agent(allowed: ["code-reviewer", "test-writer"])),
        Row(entry: "Agent()", expected: .agent(allowed: [])),
        Row(entry: "Agent( a ,b )", expected: .agent(allowed: ["a", "b"])),
        Row(entry: "Agent(b, a)", expected: .agent(allowed: ["b", "a"])),
        Row(entry: "mcp__srv", expected: .mcpPrefix("mcp__srv")),
        Row(entry: "mcp__srv__*", expected: .mcpPrefix("mcp__srv")),
        Row(entry: "mcp__*", expected: .mcpAll),
        Row(entry: "mcp__srv__tool", expected: .name("mcp__srv__tool")),
        Row(entry: "Agentx", expected: .name("Agentx")),
        Row(entry: "Agent(a", expected: .name("Agent(a")),
        Row(entry: "mcp__", expected: .name("mcp__")),
        Row(entry: "mcp__s*", expected: .name("mcp__s*")),
        Row(entry: " Read ", expected: .name("Read"))
    ]

    @Test("an entry parses to the value of its form", arguments: rows)
    func entryParsesToItsForm(row: Row) {
        #expect(ToolSpec.parse(row.entry) == row.expected)
    }

    @Test("a decoded tools text keeps the names of Agent(a, b) in one entry")
    func decodedToolsTextParsesEachEntry() throws {
        let frontmatter = try #require(AgentFrontmatter.decode("tools: Agent(code-reviewer, test-writer), Read"))
        let entries = try #require(frontmatter.tools)

        #expect(
            entries.map(ToolSpec.parse)
                == [.agent(allowed: ["code-reviewer", "test-writer"]), .name("Read")])
    }
}
