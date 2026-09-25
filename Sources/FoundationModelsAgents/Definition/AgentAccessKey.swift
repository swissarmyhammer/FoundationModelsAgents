/// A frontmatter key whose value limits what an agent can do (plan.md §4.3).
///
/// When the value of such a key is not correct, the author's limit cannot be
/// read. The key then gets a warning, and the definition uses a value that
/// gives less access, not more: the agent fails closed.
///
/// The cases are in the order of their warnings. The `disallowedTools`
/// warning comes first, because a dropped deny gives more access than the
/// author wanted (plan.md §5).
enum AgentAccessKey: String, CaseIterable, Sendable {
    /// The `disallowedTools` key. A deny that cannot be read in full gives
    /// no tools.
    case disallowedTools

    /// The `tools` key. Only its text entries give tools.
    case tools

    /// The `maxTurns` key. A value that is not a whole number greater than 0
    /// gives the limit `failClosedTurnLimit`.
    case maxTurns

    /// The limit of passes of an agent whose `maxTurns` value is not correct.
    /// It is also the smallest correct `maxTurns` value.
    static let failClosedTurnLimit = 1

    /// The warning for an incorrect value of this key.
    var finding: AgentFinding {
        AgentFinding(severity: .warning, message: "the value of '\(rawValue)' is not \(expectation); \(outcome)")
    }

    /// The value that the key must have, as the warning names it.
    private var expectation: String {
        switch self {
        case .disallowedTools, .tools:
            AgentFrontmatterValueKind.list.rawValue
        case .maxTurns:
            "\(AgentFrontmatterValueKind.wholeNumber.rawValue) not less than \(Self.failClosedTurnLimit)"
        }
    }

    /// What the definition uses in place of the value, as the warning names
    /// it.
    private var outcome: String {
        switch self {
        case .disallowedTools:
            "the deny cannot be read in full, thus the agent gets no tools"
        case .tools:
            "the agent gets only the tools of the text entries"
        case .maxTurns:
            "the limit is \(Self.failClosedTurnLimit) pass"
        }
    }

    /// Gives the keys of `frontmatter` whose value is not correct.
    ///
    /// - Parameter frontmatter: The decoded frontmatter.
    /// - Returns: The keys, in the order of their warnings.
    static func incorrectKeys(in frontmatter: AgentFrontmatter) -> [AgentAccessKey] {
        allCases.filter { key in key.isIncorrect(in: frontmatter) }
    }

    /// Tells if the value of this key in `frontmatter` is not correct: it has
    /// the wrong type, or it is a list with an item that is not text, or it
    /// is a `maxTurns` less than `failClosedTurnLimit`.
    ///
    /// - Parameter frontmatter: The decoded frontmatter.
    /// - Returns: `true` when the value is not correct.
    private func isIncorrect(in frontmatter: AgentFrontmatter) -> Bool {
        let hasWrongType = frontmatter.wrongTypeKeys.contains(rawValue)
        switch self {
        case .disallowedTools, .tools:
            return hasWrongType
        case .maxTurns:
            return hasWrongType || (frontmatter.maxTurns.map { limit in limit < Self.failClosedTurnLimit } ?? false)
        }
    }
}
