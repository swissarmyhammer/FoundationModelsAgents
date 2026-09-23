/// A tier 1 or tier 2 field of the agent frontmatter (plan.md §4.2): the
/// type that its value must have, and the property that holds it.
enum AgentFrontmatterField: Sendable {
    /// The key path of a property of `AgentFrontmatter` with a `Value?`.
    typealias Property<Value> = WritableKeyPath<AgentFrontmatter, Value?> & Sendable

    /// A text value.
    case text(Property<String>)
    /// A comma-separated text or a YAML list of text.
    case list(Property<[String]>)
    /// A whole number.
    case wholeNumber(Property<Int>)
    /// `true` or `false`.
    case flag(Property<Bool>)

    /// Each tier 1 and tier 2 field, by its key as the file writes it.
    static let byKey: [String: AgentFrontmatterField] = [
        "name": .text(\.name),
        "description": .text(\.description),
        "tools": .list(\.tools),
        "disallowedTools": .list(\.disallowedTools),
        "model": .text(\.model),
        "skills": .list(\.skills),
        "maxTurns": .wholeNumber(\.maxTurns),
        "compactionPrompt": .text(\.compactionPrompt),
        "disable-model-invocation": .flag(\.disableModelInvocation),
        "user-invocable": .flag(\.userInvocable),
        "color": .text(\.color),
        "background": .flag(\.background)
    ]
}

/// The type that the value of a frontmatter key must have.
///
/// The raw value is the name of the type in a decode note.
enum AgentFrontmatterValueKind: String {
    /// A text scalar.
    case text
    /// A YAML list of text, or one comma-separated text.
    case list = "a list of text or a comma-separated text"
    /// A whole number.
    case wholeNumber = "a whole number"
    /// `true` or `false`.
    case flag = "true or false"
}
