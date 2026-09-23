import Foundation

/// Reads the Swift blocks of `README.md` and the compiled copy of each block
/// in `ReadmeExampleSource.swift` (plan.md §15).
///
/// The compiled copy of a block is the text between two marker comments,
/// ``startMarker`` and ``endMarker``. A block is a copy when each of its
/// lines is equal to the line at the same position between the markers. The
/// comparison removes the leading and trailing whitespace of each line. Thus
/// the README can indent the example in its own style, but it cannot become
/// different from the code that compiles and runs.
///
/// A block can start with `import` lines. A function body cannot hold an
/// import, thus each leading import line of a block must be an import line
/// of the source file, and the comparison with the marker text starts after
/// the imports.
enum ReadmeExample {
    /// The comment line that starts the compiled copy of a README block.
    static let startMarker = "// README example: begin"

    /// The comment line that ends the compiled copy of a README block.
    static let endMarker = "// README example: end"

    /// The line that opens a Swift block in Markdown.
    static let swiftFence = "```swift"

    /// The line that closes each block in Markdown.
    static let closingFence = "```"

    /// The text that starts an import line.
    static let importPrefix = "import "

    /// The README of the package.
    static var readmeURL: URL {
        PackageRoot.directory.appendingPathComponent("README.md")
    }

    /// The test source that holds the compiled copy of each README block.
    static var sourceURL: URL {
        PackageRoot.directory
            .appendingPathComponent("Tests", isDirectory: true)
            .appendingPathComponent("FoundationModelsAgentsTests", isDirectory: true)
            .appendingPathComponent("ReadmeExampleSource.swift")
    }

    /// Gives the lines of each Swift block of a Markdown text.
    ///
    /// - Parameter markdown: The Markdown text.
    /// - Returns: One entry for each Swift block, in text order. Each entry
    ///   holds the trimmed lines between the fences.
    static func swiftBlocks(in markdown: String) -> [[String]] {
        sections(of: trimmedLines(of: markdown), openedBy: swiftFence, closedBy: closingFence)
    }

    /// Tells if a README block has a compiled copy in a source text.
    ///
    /// - Parameters:
    ///   - block: The trimmed lines of one README block.
    ///   - source: The text of the Swift source file.
    /// - Returns: `true` when each leading import line of `block` is an import
    ///   line of `source`, and the other lines of `block` are the lines
    ///   between one pair of markers of `source`.
    static func hasCopy(of block: [String], in source: String) -> Bool {
        let sourceLines = trimmedLines(of: source)
        let sourceImports = Set(sourceLines.filter(isImportOrBlank))
        let blockImports = block.prefix(while: isImportOrBlank)
        let code = Array(block.dropFirst(blockImports.count))
        let copies = sections(of: sourceLines, openedBy: startMarker, closedBy: endMarker)
        return sourceImports.isSuperset(of: blockImports) && copies.contains(code)
    }

    /// Gives the lines between each opening line and the next closing line.
    ///
    /// - Parameters:
    ///   - lines: The trimmed lines of a text.
    ///   - opening: The line that opens a section.
    ///   - closing: The line that closes a section.
    /// - Returns: The lines of each section, in text order. A section with no
    ///   closing line runs to the end of `lines`.
    private static func sections(
        of lines: [String], openedBy opening: String, closedBy closing: String
    ) -> [[String]] {
        lines.indices.filter { lines[$0] == opening }.map { start in
            Array(lines[lines.index(after: start)...].prefix { $0 != closing })
        }
    }

    /// Tells if a trimmed line is an import line or a blank line.
    ///
    /// - Parameter line: The trimmed line.
    /// - Returns: `true` for an import line or an empty line.
    private static func isImportOrBlank(_ line: String) -> Bool {
        line.isEmpty || line.hasPrefix(importPrefix)
    }

    /// Splits a text into lines, and removes the leading and trailing
    /// whitespace of each line.
    ///
    /// - Parameter text: The text.
    /// - Returns: The trimmed lines, in text order.
    private static func trimmedLines(of text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
