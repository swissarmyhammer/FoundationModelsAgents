import Foundation
import FoundationModelsExtras

/// One finding of the rule table before it gets a file: a severity and a
/// message.
struct AgentFinding: Sendable, Equatable {
    /// How serious the finding is.
    let severity: AgentDiagnostic.Severity

    /// The text of the finding.
    let message: String

    /// Makes the diagnostic of this finding for one file.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent, or `nil` when it is not known.
    ///   - provenance: The file that the finding is about.
    /// - Returns: The diagnostic.
    func diagnostic(agent: String?, provenance: AgentDiagnostic.Provenance) -> AgentDiagnostic {
        AgentDiagnostic(severity: severity, agent: agent, provenance: provenance, message: message)
    }
}

/// The rule table of plan.md §4.3 step 2, for the rules that one file can
/// break by itself.
///
/// The rules that need the tool catalog, the skills registry, or the profile
/// are not here. Later layers apply them.
enum AgentDefinitionRules {
    /// One rule over a frontmatter. It gets the id (the file name) and the
    /// frontmatter, and gives its findings in order.
    typealias Rule = @Sendable (String, AgentFrontmatter) -> [AgentFinding]

    /// The one character other than a letter or a digit that an id can hold.
    static let hyphen: Character = "-"

    /// Two hyphens in sequence, which an id must not hold.
    static let doubledHyphen = String(repeating: hyphen, count: 2)

    /// The frontmatter rules, in the order of their findings: the warnings
    /// first, then the advisories.
    static let frontmatterRules: [Rule] = [
        nameFindings,
        descriptionFindings,
        modelFindings,
        unsupportedKeyFindings,
        backgroundFindings,
        noteFindings,
        unknownKeyFindings
    ]

    /// The skip for a file with no frontmatter block, or with a frontmatter
    /// that did not decode after the retry.
    static let noFrontmatterFinding = AgentFinding(
        severity: .skip,
        message: "the file has no frontmatter block, or the frontmatter did not decode; the file is skipped")

    /// Tells if `id` is a valid agent id: 1 to 64 of `[a-z0-9-]`, with no
    /// leading, trailing, or doubled hyphen.
    ///
    /// - Parameter id: The file name with no `.md`.
    /// - Returns: `true` when the id is valid.
    static func isValidID(_ id: String) -> Bool {
        (1...AgentDefinition.idCharacterLimit).contains(id.count)
            && id.allSatisfy(isIDCharacter)
            && id.first != hyphen
            && id.last != hyphen
            && !id.contains(doubledHyphen)
    }

    /// The skip for a file name that is not a valid id.
    ///
    /// - Parameter id: The file name with no `.md`.
    /// - Returns: The finding.
    static func invalidIDFinding(_ id: String) -> AgentFinding {
        AgentFinding(
            severity: .skip,
            message: "the file name '\(id)' is not 1 to \(AgentDefinition.idCharacterLimit) of [a-z0-9-] "
                + "with no leading, trailing, or doubled hyphen; the file is skipped")
    }

    /// Applies each frontmatter rule.
    ///
    /// - Parameters:
    ///   - id: The file name with no `.md`.
    ///   - frontmatter: The decoded frontmatter.
    /// - Returns: The findings of all the rules, in order.
    static func findings(id: String, frontmatter: AgentFrontmatter) -> [AgentFinding] {
        frontmatterRules.flatMap { rule in rule(id, frontmatter) }
    }

    /// Tells if `text` holds a character that is not white space.
    ///
    /// - Parameter text: The value of a key, or `nil`.
    /// - Returns: `true` when the value holds text.
    static func holdsText(_ text: String?) -> Bool {
        !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Tells if `character` can be in an id.
    ///
    /// - Parameter character: One character of a file name.
    /// - Returns: `true` for an ASCII lowercase letter, an ASCII digit, or a
    ///   hyphen.
    private static func isIDCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLowercase || character.isNumber || character == hyphen)
    }

    /// The `name` rule: absent, or not equal to the file name, is a warning.
    private static func nameFindings(id: String, frontmatter: AgentFrontmatter) -> [AgentFinding] {
        guard let name = frontmatter.name else {
            return [AgentFinding(
                severity: .warning, message: "the frontmatter has no 'name'; the file name '\(id)' is the id")]
        }
        guard name != id else {
            return []
        }
        return [AgentFinding(
            severity: .warning,
            message: "the 'name' value '\(name)' is not equal to the file name '\(id)'; the file name is the id")]
    }

    /// The `description` rule: absent or empty is a warning, and longer than
    /// the limit is a warning.
    private static func descriptionFindings(id: String, frontmatter: AgentFrontmatter) -> [AgentFinding] {
        guard holdsText(frontmatter.description) else {
            return [AgentFinding(
                severity: .warning,
                message: "the frontmatter has no 'description'; the agent is not model-visible")]
        }
        guard (frontmatter.description?.count ?? 0) > AgentDefinition.descriptionCharacterLimit else {
            return []
        }
        return [AgentFinding(
            severity: .warning,
            message: "the 'description' is longer than \(AgentDefinition.descriptionCharacterLimit) characters")]
    }

    /// The `model` rule of this layer: a `model` key must hold text.
    private static func modelFindings(id: String, frontmatter: AgentFrontmatter) -> [AgentFinding] {
        guard frontmatter.model != nil, !holdsText(frontmatter.model) else {
            return []
        }
        return [AgentFinding(
            severity: .warning, message: "the 'model' value is empty; the run uses the default slot")]
    }

    /// The tier 3 rule: each tier 3 key is an advisory.
    private static func unsupportedKeyFindings(id: String, frontmatter: AgentFrontmatter) -> [AgentFinding] {
        keyFindings(frontmatter.unsupportedFields, reason: "is not supported; the key is ignored")
    }

    /// The unknown key rule: each unknown key is an advisory.
    private static func unknownKeyFindings(id: String, frontmatter: AgentFrontmatter) -> [AgentFinding] {
        keyFindings(frontmatter.unknownFields, reason: "is not known; the key is kept as data on the listing")
    }

    /// The `background` rule: `background: false` is an advisory, because
    /// each run is a background run.
    private static func backgroundFindings(id: String, frontmatter: AgentFrontmatter) -> [AgentFinding] {
        guard frontmatter.background == false else {
            return []
        }
        return [AgentFinding(
            severity: .advisory, message: "'background: false' is ignored; each run is a background run")]
    }

    /// The decode note rule: each decode note is an advisory.
    private static func noteFindings(id: String, frontmatter: AgentFrontmatter) -> [AgentFinding] {
        frontmatter.notes.map { note in AgentFinding(severity: .advisory, message: note) }
    }

    /// One advisory for each key of `fields`, in sorted key order.
    ///
    /// - Parameters:
    ///   - fields: The keys with their values.
    ///   - reason: The end of the message, after the key.
    /// - Returns: The findings.
    private static func keyFindings(_ fields: [String: YAMLValue], reason: String) -> [AgentFinding] {
        fields.keys.sorted().map { key in
            AgentFinding(severity: .advisory, message: "the key '\(key)' \(reason)")
        }
    }
}
