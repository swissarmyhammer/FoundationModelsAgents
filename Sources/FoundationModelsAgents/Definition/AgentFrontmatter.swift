import FoundationModelsExtras

/// The raw frontmatter of one agent file (plan.md §4.2).
///
/// Each field holds the value as the file writes it. This type does not
/// validate a value: `AgentDefinition` applies the rules of plan.md §4.3. A
/// field is `nil` when the file does not write the key, when the value is
/// null, or when the value has the wrong type. A wrong type also adds a note.
///
/// The frontmatter is never rendered. A `{{ x }}` in a value stays text.
public struct AgentFrontmatter: Sendable, Equatable {
    /// The `name` key. It must be equal to the file name.
    public var name: String?

    /// The `description` key. It tells the model when to use the agent.
    public var description: String?

    /// The `tools` key: the tool entries that the agent can use.
    public var tools: [String]?

    /// The `disallowedTools` key: the tool entries that the agent cannot use.
    public var disallowedTools: [String]?

    /// The `model` key, as text. The runner matches it to a slot (plan.md §7).
    public var model: String?

    /// The `skills` key: the skills to load into the instructions of a run.
    public var skills: [String]?

    /// The `maxTurns` key: the maximum count of passes through the tool loop.
    public var maxTurns: Int?

    /// The `compactionPrompt` key: the fold prompt of this agent.
    public var compactionPrompt: String?

    /// The `disable-model-invocation` key.
    public var disableModelInvocation: Bool?

    /// The `user-invocable` key.
    public var userInvocable: Bool?

    /// The `color` key (tier 2, data only).
    public var color: String?

    /// The `background` key (tier 2, data only).
    public var background: Bool?

    /// The tier 3 keys that the file writes, with their values. This package
    /// does not support them. They are kept for the advisories.
    public var unsupportedFields: [String: YAMLValue]

    /// The keys that this package does not know, with their values. They are
    /// kept for the advisories and for `AgentListing`.
    public var unknownFields: [String: YAMLValue]

    /// The decode notes: a value of the wrong type, or a colon retry.
    public var notes: [String]

    /// Creates a frontmatter from its field values.
    ///
    /// - Parameters:
    ///   - name: The `name` key.
    ///   - description: The `description` key.
    ///   - tools: The `tools` key.
    ///   - disallowedTools: The `disallowedTools` key.
    ///   - model: The `model` key.
    ///   - skills: The `skills` key.
    ///   - maxTurns: The `maxTurns` key.
    ///   - compactionPrompt: The `compactionPrompt` key.
    ///   - disableModelInvocation: The `disable-model-invocation` key.
    ///   - userInvocable: The `user-invocable` key.
    ///   - color: The `color` key.
    ///   - background: The `background` key.
    ///   - unsupportedFields: The tier 3 keys with their values.
    ///   - unknownFields: The unknown keys with their values.
    ///   - notes: The decode notes.
    public init(
        name: String? = nil,
        description: String? = nil,
        tools: [String]? = nil,
        disallowedTools: [String]? = nil,
        model: String? = nil,
        skills: [String]? = nil,
        maxTurns: Int? = nil,
        compactionPrompt: String? = nil,
        disableModelInvocation: Bool? = nil,
        userInvocable: Bool? = nil,
        color: String? = nil,
        background: Bool? = nil,
        unsupportedFields: [String: YAMLValue] = [:],
        unknownFields: [String: YAMLValue] = [:],
        notes: [String] = []
    ) {
        self.name = name
        self.description = description
        self.tools = tools
        self.disallowedTools = disallowedTools
        self.model = model
        self.skills = skills
        self.maxTurns = maxTurns
        self.compactionPrompt = compactionPrompt
        self.disableModelInvocation = disableModelInvocation
        self.userInvocable = userInvocable
        self.color = color
        self.background = background
        self.unsupportedFields = unsupportedFields
        self.unknownFields = unknownFields
        self.notes = notes
    }
}

extension AgentFrontmatter {
    /// The tier 3 keys of plan.md §4.2. A file with one of them loads, and
    /// the key gets an advisory.
    static let unsupportedKeys: Set<String> = [
        "permissionMode", "mcpServers", "hooks", "memory", "effort", "isolation", "initialPrompt"
    ]

    /// The note that a decode records when the colon retry made it succeed.
    static let colonRetryNote =
        "the frontmatter YAML did not decode until the unquoted 'description:' value was put in quotes"

    /// The note for a value that does not have the type of its key.
    ///
    /// - Parameters:
    ///   - key: The key as the file writes it.
    ///   - expected: The type that the key must have.
    /// - Returns: The text of the note.
    static func wrongTypeNote(key: String, expected: AgentFrontmatterValueKind) -> String {
        "the value of '\(key)' is not \(expected.rawValue); the value is ignored"
    }

    /// Decodes the raw frontmatter text of one agent file.
    ///
    /// The signature is the `decode` of `FrontmatterDocumentStack`. The parse
    /// is `YAMLValue.parse(_:)`, which uses Yams. The decode never throws.
    ///
    /// When the text does not parse, the decode retries one time with the
    /// Skills rule: it puts an unquoted `description:` value in quotes. A
    /// retry that succeeds adds `colonRetryNote`.
    ///
    /// - Parameter yaml: The text between the `---` fences.
    /// - Returns: The frontmatter. An empty text gives a frontmatter with no
    ///   fields. `nil` when the text does not parse after the retry, or when
    ///   its top level is not a mapping.
    public static func decode(_ yaml: String) -> AgentFrontmatter? {
        if let frontmatter = decodeOnce(yaml) {
            return frontmatter
        }
        guard let retried = DescriptionColonRetry.quotingDescription(in: yaml),
            var frontmatter = decodeOnce(retried)
        else {
            return nil
        }
        frontmatter.notes.append(colonRetryNote)
        return frontmatter
    }

    /// Parses `yaml` one time and reads its top-level mapping.
    ///
    /// - Parameter yaml: The frontmatter text.
    /// - Returns: The frontmatter, or `nil` when the text does not parse or
    ///   its top level is not a mapping.
    private static func decodeOnce(_ yaml: String) -> AgentFrontmatter? {
        guard let tree = try? YAMLValue.parse(yaml) else {
            return nil
        }
        switch tree {
        case .null:
            return AgentFrontmatter()
        case .dictionary(let fields):
            return AgentFrontmatterReader.read(fields)
        case .string, .int, .double, .bool, .array:
            return nil
        }
    }
}
