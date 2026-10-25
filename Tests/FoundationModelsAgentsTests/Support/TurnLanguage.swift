import Foundation

/// Finds turn language in a text for the model.
///
/// The model works without turns (the rule of the user for each text that
/// the model reads): a result and mail come in as messages, and the text
/// that the model writes is a status message to whoever started it. Thus no
/// text for the model tells it to end an answer, waits for its turn, or asks
/// it for no text.
enum TurnLanguage {
    /// The phrases that no text for the model may hold, in lower case.
    static let bannedPhrases = ["end your", "when you end", "starts you", "write no text"]

    /// The words that no text for the model may hold as a full word, in
    /// lower case. A word inside a longer name, such as the key `maxTurns`
    /// or the word `return`, is not reported.
    static let bannedWords = ["turn", "turns"]

    /// Finds each phrase and each word of the turn language in `text`.
    ///
    /// The search ignores case.
    ///
    /// - Parameter text: The text to read.
    /// - Returns: Each phrase and word that `text` holds, in list order. It
    ///   is empty when `text` holds none.
    static func phrases(in text: String) -> [String] {
        let lowered = text.lowercased()
        let foundPhrases = bannedPhrases.filter { lowered.contains($0) }
        let foundWords = bannedWords.filter { word in
            lowered.split { !$0.isLetter }.contains { $0 == word }
        }
        return foundPhrases + foundWords
    }

    /// Gives the text of the string literals of `lines`, one entry for each
    /// line.
    ///
    /// A line of a multi-line literal gives all its text. A line of code
    /// gives the text between its quotes, with each escaped quote removed
    /// first. A comment line gives no text, and a line that opens or closes a
    /// multi-line literal gives only the text of its other literals.
    ///
    /// - Parameter lines: The lines of a Swift source text, in order.
    /// - Returns: The literal text of each line, in the same order.
    static func literalText(of lines: [String]) -> [String] {
        var insideMultiLine = false
        return lines.map { line in
            let marks = line.components(separatedBy: multiLineMark).count - 1
            if insideMultiLine {
                if marks % 2 == 1 {
                    insideMultiLine = false
                }
                return line.components(separatedBy: multiLineMark).first ?? ""
            }
            if SwiftSourceScan.isComment(line) {
                return ""
            }
            if marks % 2 == 1 {
                insideMultiLine = true
                return quotedText(of: line.components(separatedBy: multiLineMark).first ?? "")
            }
            return quotedText(of: line.replacingOccurrences(of: multiLineMark, with: ""))
        }
    }

    /// The text that opens and closes a multi-line string literal.
    private static let multiLineMark = "\"\"\""

    /// Gives the text between the quotes of one line of code.
    ///
    /// - Parameter line: The line, with no multi-line mark.
    /// - Returns: Each quoted part of the line, joined by a space.
    private static func quotedText(of line: String) -> String {
        line.replacingOccurrences(of: "\\\"", with: "")
            .components(separatedBy: "\"")
            .enumerated()
            .filter { $0.offset % 2 == 1 }
            .map(\.element)
            .joined(separator: " ")
    }
}
