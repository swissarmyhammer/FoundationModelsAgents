import FoundationModelsExtras

/// The template values of the tests that turn the `shell` tool group on or
/// off, and a body that tells which branch it renders.
enum ShellGroupFixture {
    /// A template text that tells if the shell group is on.
    static let gatedText = "{% if tools.shell.enabled %}shell on{% else %}shell off{% endif %}"

    /// The text that ``gatedText`` renders with the shell group on.
    static let onText = "shell on"

    /// The text that ``gatedText`` renders with the shell group off.
    static let offText = "shell off"

    /// Gives a template context with the shell group on or off.
    ///
    /// - Parameter enabled: The value of `tools.shell.enabled`.
    /// - Returns: The context.
    static func context(enabled: Bool) -> [String: TemplateValue] {
        ["tools": .dictionary(["shell": .dictionary(["enabled": .bool(enabled)])])]
    }
}
