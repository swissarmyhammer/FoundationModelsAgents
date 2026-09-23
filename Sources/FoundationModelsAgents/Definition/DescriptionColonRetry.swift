import Foundation

/// The colon retry of the frontmatter decode (plan.md §4.3 step 1).
///
/// This is the rule of the `FoundationModelsSkills` frontmatter decoder. A
/// Claude author often writes a `description:` value that holds an unquoted
/// `: `, for example `description: Deploy to staging: run the tests`. A
/// strict YAML parser reads it as a nested mapping and fails. The retry puts
/// the value in double quotes.
///
/// The retry changes only the one top-level line that starts with
/// `description:`. A description that continues on more lines keeps its
/// other lines, thus the retried text does not parse, and the decode fails.
enum DescriptionColonRetry {
    /// The start of the line that the retry changes. It is not indented.
    private static let linePrefix = "description:"

    /// The line end character of a text with Windows line ends.
    private static let carriageReturn = "\r"

    /// Puts the `description:` value of `yaml` in double quotes.
    ///
    /// - Parameter yaml: The frontmatter text that did not parse.
    /// - Returns: The text with the value in quotes, with each `\` and `"`
    ///   of the value escaped. `nil` when the text has no top-level
    ///   `description:` line, or when its value is empty or already in
    ///   quotes: a retry of the same text cannot succeed.
    static func quotingDescription(in yaml: String) -> String? {
        var lines = yaml.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0.hasPrefix(linePrefix) }) else {
            return nil
        }
        let line = lines[index]
        let hasCarriageReturn = line.hasSuffix(carriageReturn)
        let content = hasCarriageReturn ? String(line.dropLast()) : line
        let value = content.dropFirst(linePrefix.count).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !isQuoted(value) else {
            return nil
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        lines[index] = "\(linePrefix) \"\(escaped)\"" + (hasCarriageReturn ? carriageReturn : "")
        return lines.joined(separator: "\n")
    }

    /// Reports whether `value` starts and ends with the same quote mark.
    ///
    /// - Parameter value: The trimmed value of the `description:` line.
    /// - Returns: `true` when the value is in single or double quotes.
    private static func isQuoted(_ value: String) -> Bool {
        ["\"", "'"].contains { quote in
            value.count > 1 && value.hasPrefix(quote) && value.hasSuffix(quote)
        }
    }
}
