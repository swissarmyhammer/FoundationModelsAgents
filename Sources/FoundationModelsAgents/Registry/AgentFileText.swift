import FoundationModelsExtras
import Yams

/// The frontmatter fields of an agent that the `agents` endpoint writes
/// (D190). A field that is `nil` does not change.
struct AgentFileFields: Sendable {
    /// The `name` key: the display name.
    var name: String?

    /// The `description` key.
    var description: String?

    /// The `model` key.
    var model: String?

    /// The `color` key.
    var color: String?

    /// The `background` key.
    var background: Bool?

    /// The Markdown body, or `nil` for no change.
    var body: String?
}

/// Makes and changes the text of an `AGENT.md` from its fields.
///
/// The `agents` GraphQL endpoint edits an agent by its fields, not by the
/// full text of the file. This type turns the fields into the full text, and
/// `AgentWriter` then writes that text, the same as for the `add agent` and
/// `edit agent` operations of the `agents` tool.
enum AgentFileText {
    /// The fence line that opens and closes the frontmatter block.
    private static let fence = "---"

    /// Each text key of ``AgentFileFields``, in the order of a new file.
    private static let textKeys: [(key: String, value: KeyPath<AgentFileFields, String?>)] = [
        ("name", \.name), ("description", \.description), ("model", \.model), ("color", \.color),
    ]

    /// The key of ``AgentFileFields/background``.
    private static let backgroundKey = "background"

    /// The text of a new `AGENT.md`: a frontmatter block with each field
    /// that is not `nil`, and then the body.
    ///
    /// - Parameter fields: The fields of the new agent.
    /// - Returns: The full text of the file.
    /// - Throws: An error of the YAML emitter.
    static func make(_ fields: AgentFileFields) throws -> String {
        try changed((frontmatter: nil, body: ""), with: fields) ?? ""
    }

    /// The text of an existing `AGENT.md` with the fields that are not `nil`.
    ///
    /// A change of a frontmatter field writes the frontmatter again from its
    /// YAML node, thus the other keys stay, in their order. A change of the
    /// body only keeps the frontmatter text as it is.
    ///
    /// - Parameters:
    ///   - current: The frontmatter text and the body of the current file.
    ///   - fields: The new fields.
    /// - Returns: The full new text, or `nil` when the frontmatter is not a
    ///   YAML mapping, thus a key cannot change.
    /// - Throws: An error of the YAML emitter.
    static func changed(
        _ current: (frontmatter: String?, body: String), with fields: AgentFileFields
    ) throws -> String? {
        var frontmatter = current.frontmatter ?? ""
        let changesKeys = textKeys.contains { fields[keyPath: $0.value] != nil } || fields.background != nil
        if changesKeys {
            guard case .mapping(var mapping)? = try? Yams.compose(yaml: frontmatter) ?? .mapping([:]) else {
                return nil
            }
            for (key, value) in textKeys {
                if let text = fields[keyPath: value] {
                    mapping[key] = quoted(text)
                }
            }
            if let background = fields.background {
                mapping[backgroundKey] = Node(background ? "true" : "false", Tag(.bool))
            }
            frontmatter = try Yams.serialize(node: .mapping(mapping))
        }
        return joined(frontmatter: frontmatter, body: fields.body ?? current.body)
    }

    /// A scalar node of `text` that the emitter writes in double quotes,
    /// thus each text reads back as the same string.
    ///
    /// - Parameter text: The text.
    /// - Returns: The node.
    private static func quoted(_ text: String) -> Node {
        Node(text, Tag(.str), .doubleQuoted)
    }

    /// The frontmatter block and the body as one text.
    ///
    /// - Parameters:
    ///   - frontmatter: The YAML text between the fences.
    ///   - body: The body.
    /// - Returns: The full text of the file.
    private static func joined(frontmatter: String, body: String) -> String {
        let block = frontmatter.isEmpty || frontmatter.hasSuffix("\n") ? frontmatter : frontmatter + "\n"
        let text = body.isEmpty || body.hasSuffix("\n") ? body : body + "\n"
        return "\(fence)\n\(block)\(fence)\n\(text)"
    }
}
