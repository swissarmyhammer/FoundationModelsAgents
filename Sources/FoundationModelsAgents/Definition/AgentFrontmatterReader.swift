import Foundation
import FoundationModelsExtras

/// Reads the top-level mapping of one agent frontmatter into
/// `AgentFrontmatter`.
///
/// The reader puts each tier 1 and tier 2 key into its field, each tier 3
/// key into `unsupportedFields`, and each other key into `unknownFields`. A
/// value of the wrong type is left out, and the reader adds a note. The
/// reader reads the keys in sorted order, thus the notes have a stable order.
struct AgentFrontmatterReader {
    /// The frontmatter that the reader fills in.
    private var frontmatter = AgentFrontmatter()

    /// Reads `fields` into a new frontmatter.
    ///
    /// - Parameter fields: The top-level mapping of the frontmatter.
    /// - Returns: The frontmatter, with a note for each value of the wrong
    ///   type.
    static func read(_ fields: [String: YAMLValue]) -> AgentFrontmatter {
        var reader = AgentFrontmatterReader()
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            reader.read(value, forKey: key)
        }
        return reader.frontmatter
    }

    /// Splits a comma-separated text into its entries.
    ///
    /// A comma in parentheses does not split, thus `Agent(a, b)` stays one
    /// entry. Each entry is trimmed, and an empty entry is removed.
    ///
    /// - Parameter text: The text of the value.
    /// - Returns: The entries in their order.
    static func entries(inCommaSeparated text: String) -> [String] {
        var entries: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            if character == "," && depth == 0 {
                entries.append(current)
                current = ""
                continue
            }
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(depth - 1, 0)
            }
            current.append(character)
        }
        entries.append(current)
        return entries.map(Self.trimmed).filter { !$0.isEmpty }
    }

    /// Removes the white space at the two ends of `text`.
    ///
    /// - Parameter text: The text to trim.
    /// - Returns: The trimmed text.
    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Puts `value` into the field of `key`.
    ///
    /// - Parameters:
    ///   - value: The value of the key.
    ///   - key: The key as the file writes it.
    private mutating func read(_ value: YAMLValue, forKey key: String) {
        if let field = AgentFrontmatterField.byKey[key] {
            read(value, into: field, key: key)
        } else if AgentFrontmatter.unsupportedKeys.contains(key) {
            frontmatter.unsupportedFields[key] = value
        } else {
            frontmatter.unknownFields[key] = value
        }
    }

    /// Puts `value` into the property of a tier 1 or tier 2 field.
    ///
    /// - Parameters:
    ///   - value: The value of the key.
    ///   - field: The field of the key.
    ///   - key: The key as the file writes it, for the note.
    private mutating func read(_ value: YAMLValue, into field: AgentFrontmatterField, key: String) {
        switch field {
        case .text(let property): frontmatter[keyPath: property] = text(value, for: key)
        case .list(let property): frontmatter[keyPath: property] = list(value, for: key)
        case .wholeNumber(let property): frontmatter[keyPath: property] = wholeNumber(value, for: key)
        case .flag(let property): frontmatter[keyPath: property] = flag(value, for: key)
        }
    }

    /// Reads a text value.
    ///
    /// - Parameters:
    ///   - value: The value of the key.
    ///   - key: The key, for the note.
    /// - Returns: The text, or `nil` for null or for the wrong type.
    private mutating func text(_ value: YAMLValue, for key: String) -> String? {
        switch value {
        case .null: return nil
        case .string(let text): return text
        case .int, .double, .bool, .array, .dictionary: return wrongType(of: key, expected: .text)
        }
    }

    /// Reads a list value: a comma-separated text or a YAML list of text.
    ///
    /// - Parameters:
    ///   - value: The value of the key.
    ///   - key: The key, for the note.
    /// - Returns: The entries, or `nil` for null or for the wrong type.
    private mutating func list(_ value: YAMLValue, for key: String) -> [String]? {
        switch value {
        case .null: return nil
        case .string(let text): return Self.entries(inCommaSeparated: text)
        case .array(let items): return listEntries(items, for: key)
        case .int, .double, .bool, .dictionary: return wrongType(of: key, expected: .list)
        }
    }

    /// Reads the items of a YAML list. An item that is not text is left out
    /// with one note for the list.
    ///
    /// - Parameters:
    ///   - items: The items of the list.
    ///   - key: The key, for the note.
    /// - Returns: The trimmed text items that are not empty.
    private mutating func listEntries(_ items: [YAMLValue], for key: String) -> [String] {
        let texts = items.compactMap { item -> String? in
            guard case .string(let text) = item else { return nil }
            return text
        }
        if texts.count != items.count {
            addWrongTypeNote(for: key, expected: .list)
        }
        return texts.map(Self.trimmed).filter { !$0.isEmpty }
    }

    /// Reads a whole-number value.
    ///
    /// - Parameters:
    ///   - value: The value of the key.
    ///   - key: The key, for the note.
    /// - Returns: The number, or `nil` for null or for the wrong type.
    private mutating func wholeNumber(_ value: YAMLValue, for key: String) -> Int? {
        switch value {
        case .null: return nil
        case .int(let number): return number
        case .string, .double, .bool, .array, .dictionary: return wrongType(of: key, expected: .wholeNumber)
        }
    }

    /// Reads a `true` or `false` value.
    ///
    /// - Parameters:
    ///   - value: The value of the key.
    ///   - key: The key, for the note.
    /// - Returns: The flag, or `nil` for null or for the wrong type.
    private mutating func flag(_ value: YAMLValue, for key: String) -> Bool? {
        switch value {
        case .null: return nil
        case .bool(let flag): return flag
        case .string, .int, .double, .array, .dictionary: return wrongType(of: key, expected: .flag)
        }
    }

    /// Adds the wrong-type note of `key`, and gives no value.
    ///
    /// - Parameters:
    ///   - key: The key whose value has the wrong type.
    ///   - expected: The type that the key must have.
    /// - Returns: `nil`, because the value is ignored.
    private mutating func wrongType<Value>(of key: String, expected: AgentFrontmatterValueKind) -> Value? {
        addWrongTypeNote(for: key, expected: expected)
        return nil
    }

    /// Adds the wrong-type note of `key`.
    ///
    /// - Parameters:
    ///   - key: The key whose value has the wrong type.
    ///   - expected: The type that the key must have.
    private mutating func addWrongTypeNote(for key: String, expected: AgentFrontmatterValueKind) {
        frontmatter.notes.append(AgentFrontmatter.wrongTypeNote(key: key, expected: expected))
    }
}
