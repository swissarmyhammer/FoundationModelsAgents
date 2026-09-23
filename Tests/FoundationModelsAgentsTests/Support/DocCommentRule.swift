import Foundation

/// The doc comment rule of `DocumentationTests`: each public declaration and
/// each enum case of the source has a doc comment.
///
/// A doc comment is a `///` line directly above the declaration. Attribute
/// lines, also an attribute whose arguments go on for more than one line, can
/// stand between the doc comment and the declaration. A blank line or a plain
/// `//` comment line cuts the doc comment from the declaration, thus the rule
/// reports the declaration.
///
/// A public declaration is a line whose leading words, before the keyword of
/// the declaration, hold `public` or `open`. An attribute on the same line
/// must have no space in its arguments. An enum case is a line that opens with
/// `case` and a lower-case name, and does not end with `:`. Thus the case of a
/// `switch` is not an enum case.
enum DocCommentRule {
    /// The text that opens a doc comment line.
    private static let docCommentMarker = "///"

    /// The character that opens an attribute.
    private static let attributeMarker = "@"

    /// The text that opens an enum case line.
    private static let enumCaseMarker = "case "

    /// The character that ends the pattern of a `switch` case.
    private static let switchCaseEnd = ":"

    /// The modifiers that make a declaration public.
    private static let publicModifiers: Set = ["public", "open"]

    /// The words that can stand before the keyword of a declaration, in
    /// addition to an attribute.
    private static let modifiers: Set = [
        "public", "open", "internal", "fileprivate", "private", "final", "static", "class",
        "nonisolated", "override", "mutating", "nonmutating", "convenience", "required",
        "indirect", "lazy", "weak", "unowned", "dynamic", "private(set)", "internal(set)",
        "fileprivate(set)"
    ]

    /// The words after `case` that open a pattern, not the name of an enum
    /// case.
    private static let patternWords: Set = ["let", "var", "is", "nil", "true", "false"]

    /// Finds each public declaration and each enum case of `lines` that has
    /// no doc comment.
    ///
    /// - Parameter lines: The lines of a Swift source text, in order.
    /// - Returns: The number of each line that declares such a symbol with no
    ///   doc comment. The first line is 1.
    static func undocumentedLines(in lines: [String]) -> [Int] {
        var walk = Walk()
        return SwiftSourceScan.lineNumbers(of: lines.map { walk.read($0) })
    }

    /// Tells whether `line` declares a symbol that the rule reads.
    ///
    /// - Parameter line: One line of source, with no leading spaces.
    /// - Returns: `true` for a public declaration and for an enum case.
    private static func declaresADocumentedSymbol(_ line: String) -> Bool {
        !SwiftSourceScan.isComment(line) && (declaresAPublicSymbol(line) || declaresAnEnumCase(line))
    }

    /// Tells whether the leading words of `line` hold `public` or `open`.
    ///
    /// - Parameter line: One line of source, with no leading spaces.
    /// - Returns: `true` when a public modifier stands before the keyword of
    ///   the declaration.
    private static func declaresAPublicSymbol(_ line: String) -> Bool {
        line.split(separator: " ")
            .lazy
            .map(String.init)
            .prefix { $0.hasPrefix(attributeMarker) || modifiers.contains($0) }
            .contains { publicModifiers.contains($0) }
    }

    /// Tells whether `line` declares an enum case.
    ///
    /// - Parameter line: One line of source, with no leading spaces.
    /// - Returns: `true` when the line opens with `case` and a lower-case
    ///   name, and does not end with `:`.
    private static func declaresAnEnumCase(_ line: String) -> Bool {
        let words = line.dropFirst(enumCaseMarker.count).split(separator: " ")
        let name = words.first.map(String.init) ?? ""
        return line.hasPrefix(enumCaseMarker)
            && !line.hasSuffix(switchCaseEnd)
            && name.first?.isLowercase == true
            && !patternWords.contains(name)
    }

    /// Gives the change in the count of open parentheses over `line`.
    ///
    /// - Parameter line: One line of source.
    /// - Returns: The count of `(` less the count of `)`.
    private static func parenthesisBalance(of line: String) -> Int {
        line.count { $0 == "(" } - line.count { $0 == ")" }
    }

    /// The state of a walk over the lines of one source text, from the top.
    private struct Walk {
        /// `true` when a doc comment stands above the line that comes next,
        /// with only attribute lines between them.
        private var isDocumented = false

        /// The count of parentheses that an attribute opened and did not
        /// close. While it is above zero, each line is a part of that
        /// attribute.
        private var openAttributeParentheses = Int.zero

        /// Reads the next line of the text.
        ///
        /// - Parameter line: The next line.
        /// - Returns: `true` when the line declares a symbol that the rule
        ///   reads, and no doc comment stands above it.
        mutating func read(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if openAttributeParentheses > .zero {
                openAttributeParentheses += DocCommentRule.parenthesisBalance(of: trimmed)
                return false
            }
            if DocCommentRule.declaresADocumentedSymbol(trimmed) {
                defer { isDocumented = false }
                return !isDocumented
            }
            if trimmed.hasPrefix(DocCommentRule.attributeMarker) {
                openAttributeParentheses = max(.zero, DocCommentRule.parenthesisBalance(of: trimmed))
                return false
            }
            isDocumented = trimmed.hasPrefix(DocCommentRule.docCommentMarker)
            return false
        }
    }
}
