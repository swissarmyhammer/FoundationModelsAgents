import Foundation

/// Finds the relative links of a Markdown text for a suite that checks a
/// document of the package (plan.md §14, M8).
///
/// A link target is the text in the parentheses directly after `]`. A
/// relative link has no URL scheme and does not start with `#`. The part
/// after `#` names a heading, thus it is not a part of the file path.
enum MarkdownLinks {
    /// The text between the label and the target of a link.
    private static let targetOpening = "]("

    /// The character that closes the target of a link.
    private static let targetClosing: Character = ")"

    /// The character that starts the heading part of a link target.
    private static let fragmentMarker: Character = "#"

    /// The character that ends the URL scheme of a link target.
    private static let schemeMarker: Character = ":"

    /// Gives the file path of each relative link of a Markdown text.
    ///
    /// - Parameter markdown: The Markdown text.
    /// - Returns: The path of each relative link, in text order, with no
    ///   heading part.
    static func relativePaths(in markdown: String) -> [String] {
        Array(
            markdown.components(separatedBy: targetOpening)
                .dropFirst()
                .lazy.map { String($0.prefix { character in character != targetClosing && !character.isWhitespace }) }
                .filter(isRelative)
                .map { String($0.prefix { character in character != fragmentMarker }) })
    }

    /// Gives each relative link of a Markdown text that names no file or
    /// folder.
    ///
    /// - Parameters:
    ///   - markdown: The Markdown text.
    ///   - directory: The folder of the Markdown file. Each relative link
    ///     resolves from it.
    /// - Returns: The path of each relative link that does not resolve, in
    ///   text order.
    static func missingPaths(in markdown: String, relativeTo directory: URL) -> [String] {
        relativePaths(in: markdown).filter { path in
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).standardized.path)
        }
    }

    /// Tells whether a link target is relative.
    ///
    /// - Parameter target: The text of a link target.
    /// - Returns: `true` when the target is not empty, has no URL scheme, and
    ///   does not start with `#`.
    private static func isRelative(_ target: String) -> Bool {
        !target.isEmpty && target.first != fragmentMarker && !target.contains(schemeMarker)
    }
}
