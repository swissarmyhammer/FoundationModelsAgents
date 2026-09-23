import Foundation

/// Reads the Swift source of this package for a suite that guards a rule of
/// the code.
///
/// Each guard suite of plan.md §15 gives this reader a test of a line, and
/// this file does the steps under it: it counts the lines of a text, it walks
/// the Swift files of a directory, it finds a comment line, and it finds a
/// full token in a line. Thus no guard suite keeps a copy of those steps.
/// `LoadingBoundaryTests` is the first guard suite.
enum SwiftSourceScan {
    /// The number of the first line of a file.
    private static let firstLineNumber = 1

    /// The suffix of a Swift source file.
    private static let swiftFileSuffix = ".swift"

    /// The text that opens a comment line.
    private static let commentMarker = "//"

    /// The character that is part of a name, in addition to a letter and a
    /// digit.
    private static let nameConnector: Character = "_"

    /// What stops a walk over a directory.
    enum ScanError: Error, CustomStringConvertible {
        /// The directory holds no Swift file, thus the walk proves nothing.
        case noSwiftFile(directory: String)

        /// The text of the error.
        var description: String {
            switch self {
            case .noSwiftFile(let directory):
                "the walk found no Swift file under \(directory), thus it proves nothing"
            }
        }
    }

    /// Finds each line of `lines` that `isReported` reports.
    ///
    /// - Parameters:
    ///   - lines: The lines of a source text, in order.
    ///   - isReported: Tells whether one line breaks the rule.
    /// - Returns: The number of each reported line. The first line is 1.
    static func lineNumbers(in lines: [String], matching isReported: (String) -> Bool) -> [Int] {
        lines.enumerated()
            .filter { isReported($0.element) }
            .map { $0.offset + firstLineNumber }
    }

    /// Finds each line of `text` that `isReported` reports.
    ///
    /// - Parameters:
    ///   - text: The source text to read.
    ///   - isReported: Tells whether one line breaks the rule.
    /// - Returns: The number of each reported line. The first line is 1.
    static func lineNumbers(in text: String, matching isReported: (String) -> Bool) -> [Int] {
        lineNumbers(in: text.components(separatedBy: .newlines), matching: isReported)
    }

    /// Tells whether `line` is a comment line. A comment line holds no code.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line, after its leading spaces, opens with
    ///   `//`. A doc comment opens with `//` too.
    static func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(commentMarker)
    }

    /// Tells whether `line` holds `token` as a full token, not as a part of a
    /// longer name.
    ///
    /// An occurrence of `token` is a full token when no letter, digit or
    /// underscore stands before it. When `token` ends with a letter, a digit
    /// or an underscore, no such character may stand after it too. Thus
    /// `print(` is not a token of `sprint(x)`, and `ForkableTool` is not a
    /// token of `ForkableToolFixture`.
    ///
    /// - Parameters:
    ///   - token: The text to look for.
    ///   - line: The line to read.
    /// - Returns: `true` when one occurrence of `token` is a full token.
    static func holds(token: String, in line: String) -> Bool {
        var start = line.startIndex
        while let found = line.range(of: token, range: start..<line.endIndex) {
            if isFullToken(found, of: token, in: line) {
                return true
            }
            start = found.upperBound
        }
        return false
    }

    /// Tells whether the occurrence `found` of `token` is a full token.
    ///
    /// - Parameters:
    ///   - found: The range of one occurrence of `token` in `line`.
    ///   - token: The text of the occurrence.
    ///   - line: The line that holds the occurrence.
    /// - Returns: `true` when no name goes on before the occurrence, and no
    ///   name of the token goes on after it.
    private static func isFullToken(_ found: Range<String.Index>, of token: String, in line: String) -> Bool {
        let tokenEndsInAName = token.last.map(isNameCharacter) ?? false
        let nameGoesOnBefore = found.lowerBound > line.startIndex
            && isNameCharacter(line[line.index(before: found.lowerBound)])
        let nameGoesOnAfter = found.upperBound < line.endIndex && isNameCharacter(line[found.upperBound])
        return !nameGoesOnBefore && !(tokenEndsInAName && nameGoesOnAfter)
    }

    /// Tells whether `character` can be a part of a Swift name.
    ///
    /// - Parameter character: The character to read.
    /// - Returns: `true` for a letter, a digit and an underscore.
    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == nameConnector
    }

    /// Finds each reported line of each Swift file under `directory`.
    ///
    /// - Parameters:
    ///   - directory: A directory path relative to the package root, such as
    ///     `"Sources"`.
    ///   - isReported: Tells whether one line breaks the rule.
    /// - Returns: One text for each reported line, in the form
    ///   `<directory>/<relative path>:<line number>`.
    /// - Throws: ``ScanError/noSwiftFile(directory:)`` when the directory
    ///   holds no Swift file, because a walk that reads no file proves
    ///   nothing. Also an error when the directory or a file of it is
    ///   unreadable, or when a file is not UTF-8 text.
    static func reportedLines(
        inDirectory directory: String, matching isReported: (String) -> Bool
    ) throws -> [String] {
        let root = PackageRoot.directory.appendingPathComponent(directory, isDirectory: true)
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(swiftFileSuffix) }
            .sorted()
        if files.isEmpty {
            throw ScanError.noSwiftFile(directory: directory)
        }

        return try files.flatMap { relativePath in
            let text = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
            return lineNumbers(in: text, matching: isReported).map { "\(directory)/\(relativePath):\($0)" }
        }
    }
}
