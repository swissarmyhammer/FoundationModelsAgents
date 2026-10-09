@testable import FoundationModelsAgents
import Testing

/// The rows of `AgentDefinitionTests`: one row for each rule of the rule
/// table, and one row for each visibility case.
enum AgentDefinitionRows {
    /// One `broken/` fixture and the result that the rule table must give.
    struct BrokenRow: Sendable, CustomTestStringConvertible {
        /// The file name of the fixture, with no `.md`.
        let id: String

        /// The severities that the attempt must give, in order.
        let severities: [AgentDiagnostic.Severity]

        /// `true` when the file must load.
        let loads: Bool

        /// The file name, as the name of the test case.
        var testDescription: String {
            "broken/agents/\(id).md"
        }
    }

    /// One inline frontmatter and the severities that the attempt must give.
    struct InlineRow: Sendable, CustomTestStringConvertible {
        /// The name of the rule that the row checks.
        let rule: String

        /// The frontmatter text between the fences.
        let yaml: String

        /// The severities that the attempt must give, in order.
        let severities: [AgentDiagnostic.Severity]

        /// The name of the rule, as the name of the test case.
        var testDescription: String {
            rule
        }
    }

    /// One file name and whether the name rule accepts it.
    struct IDRow: Sendable, CustomTestStringConvertible {
        /// The file name, with no `.md`.
        let id: String

        /// `true` when the name rule accepts the file name.
        let isValid: Bool

        /// The file name, as the name of the test case.
        var testDescription: String {
            "`\(id)`"
        }
    }

    /// One `tools`, `disallowedTools`, or `maxTurns` value that the author
    /// wrote incorrectly, and the values that give less access.
    struct AccessRow: Sendable, CustomTestStringConvertible {
        /// The name of the case that the row checks.
        let rule: String

        /// The frontmatter lines after the clean `name` and `description`.
        let yaml: String

        /// The key that the warning must name.
        let key: String

        /// The value that `tools` must have.
        let tools: [String]?

        /// The value that `maxTurns` must have.
        let maxTurns: Int?

        /// The name of the case, as the name of the test case.
        var testDescription: String {
            rule
        }
    }

    /// One pair of visibility keys and the visibility that they must give.
    struct VisibilityRow: Sendable, CustomTestStringConvertible {
        /// The frontmatter text between the fences.
        let yaml: String

        /// The value that `isModelVisible` must have.
        let isModelVisible: Bool

        /// The value that `isUserInvocable` must have.
        let isUserInvocable: Bool

        /// The frontmatter text, as the name of the test case.
        var testDescription: String {
            yaml.replacingOccurrences(of: "\n", with: "; ")
        }
    }

    /// The `name` and `description` lines of a clean inline file.
    static let cleanLines = "name: \(AgentDefinitionAttempt.inlineID)\n\(AgentDefinitionAttempt.validDescription)"

    /// A description one character longer than the limit.
    static let longDescription = String(
        repeating: "d", count: AgentDefinition.descriptionCharacterLimit + 1)

    /// A file name of the maximum length.
    static let longestID = String(repeating: "a", count: AgentDefinition.idCharacterLimit)

    /// The `broken/` fixtures, with their results.
    static let broken: [BrokenRow] = [
        BrokenRow(id: "bad-name", severities: [.warning], loads: true),
        BrokenRow(id: "Bad_Name", severities: [.skip], loads: false),
        BrokenRow(id: "no-frontmatter", severities: [.skip], loads: false),
        BrokenRow(id: "missing-description", severities: [.warning], loads: true),
        BrokenRow(id: "bad-colon-description", severities: [.advisory], loads: true),
        BrokenRow(id: "unknown-model", severities: [], loads: true),
        BrokenRow(id: "unknown-disallowed-tool", severities: [], loads: true)
    ]

    /// The inline rows: one row for each rule of the table that a
    /// frontmatter can break.
    static let inline: [InlineRow] = [
        InlineRow(rule: "a clean file", yaml: cleanLines, severities: []),
        InlineRow(rule: "no name", yaml: AgentDefinitionAttempt.validDescription, severities: [.warning]),
        InlineRow(
            rule: "an other name", yaml: "name: other\n\(AgentDefinitionAttempt.validDescription)",
            severities: [.warning]),
        InlineRow(rule: "no description", yaml: "name: \(AgentDefinitionAttempt.inlineID)", severities: [.warning]),
        InlineRow(
            rule: "an empty description", yaml: "name: \(AgentDefinitionAttempt.inlineID)\ndescription: \"  \"",
            severities: [.warning]),
        InlineRow(
            rule: "a long description",
            yaml: "name: \(AgentDefinitionAttempt.inlineID)\ndescription: \(longDescription)",
            severities: [.warning]),
        InlineRow(rule: "an empty model", yaml: "\(cleanLines)\nmodel: \"\"", severities: [.warning]),
        InlineRow(rule: "a tier 3 key", yaml: "\(cleanLines)\nmemory: project", severities: [.advisory]),
        InlineRow(rule: "background false", yaml: "\(cleanLines)\nbackground: false", severities: [.advisory]),
        InlineRow(rule: "background true", yaml: "\(cleanLines)\nbackground: true", severities: []),
        InlineRow(rule: "a data key of the wrong type", yaml: "\(cleanLines)\ncolor: [blue]", severities: [.advisory]),
        InlineRow(rule: "an unknown key", yaml: "\(cleanLines)\nowner: docs-team", severities: [.advisory])
    ]

    /// The limit of passes that a `maxTurns` value that is not correct gives.
    static let turnLimitOfBadValue = 1

    /// The `tools`, `disallowedTools`, and `maxTurns` cases of the rule
    /// table. Each gives one warning and less access.
    static let access: [AccessRow] = [
        AccessRow(rule: "tools of the wrong type", yaml: "tools: 3", key: "tools", tools: [], maxTurns: nil),
        AccessRow(
            rule: "a tools list with an item that is not text", yaml: "tools: [Read, 3]", key: "tools",
            tools: ["Read"], maxTurns: nil),
        AccessRow(
            rule: "disallowedTools of the wrong type", yaml: "disallowedTools: {Bash: true}",
            key: "disallowedTools", tools: [], maxTurns: nil),
        AccessRow(
            rule: "a disallowedTools list with an item that is not text", yaml: "disallowedTools: [Bash, 3]",
            key: "disallowedTools", tools: [], maxTurns: nil),
        AccessRow(
            rule: "maxTurns of the wrong type", yaml: "maxTurns: \"5\"", key: "maxTurns", tools: nil,
            maxTurns: turnLimitOfBadValue),
        AccessRow(
            rule: "maxTurns of 0", yaml: "maxTurns: 0", key: "maxTurns", tools: nil, maxTurns: turnLimitOfBadValue),
        AccessRow(
            rule: "maxTurns less than 0", yaml: "maxTurns: -3", key: "maxTurns", tools: nil,
            maxTurns: turnLimitOfBadValue)
    ]

    /// The file names of the name rule.
    static let ids: [IDRow] = [
        IDRow(id: "a", isValid: true),
        IDRow(id: "code-reviewer", isValid: true),
        IDRow(id: "agent-2", isValid: true),
        IDRow(id: longestID, isValid: true),
        IDRow(id: "", isValid: false),
        IDRow(id: longestID + "a", isValid: false),
        IDRow(id: "Bad_Name", isValid: false),
        IDRow(id: "code_reviewer", isValid: false),
        IDRow(id: "Reviewer", isValid: false),
        IDRow(id: "-reviewer", isValid: false),
        IDRow(id: "reviewer-", isValid: false),
        IDRow(id: "code--reviewer", isValid: false),
        IDRow(id: "revi\u{00E9}wer", isValid: false)
    ]

    /// The visibility keys, with the visibility that they must give.
    static let visibility: [VisibilityRow] = [
        VisibilityRow(yaml: AgentDefinitionAttempt.validDescription, isModelVisible: true, isUserInvocable: true),
        VisibilityRow(
            yaml: "\(AgentDefinitionAttempt.validDescription)\ndisable-model-invocation: true",
            isModelVisible: false, isUserInvocable: true),
        VisibilityRow(
            yaml: "\(AgentDefinitionAttempt.validDescription)\ndisable-model-invocation: false",
            isModelVisible: true, isUserInvocable: true),
        VisibilityRow(
            yaml: "\(AgentDefinitionAttempt.validDescription)\nuser-invocable: false",
            isModelVisible: true, isUserInvocable: false),
        VisibilityRow(
            yaml: "\(AgentDefinitionAttempt.validDescription)\nuser-invocable: true",
            isModelVisible: true, isUserInvocable: true),
        VisibilityRow(yaml: "name: \(AgentDefinitionAttempt.inlineID)", isModelVisible: false, isUserInvocable: true),
        VisibilityRow(yaml: "description: \"\"", isModelVisible: false, isUserInvocable: true)
    ]
}
