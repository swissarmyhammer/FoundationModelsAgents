import FoundationModels

/// A tool with no behavior for the tool resolution tests.
///
/// It is a class, thus two instances have two identities, and a test can
/// tell that each factory call gave a new instance.
final class ProbeTool: Tool {
    /// The arguments of the tool: one text.
    @Generable
    struct Arguments {
        /// A text that the tool ignores.
        let text: String
    }

    /// The name of the tool.
    let name: String

    /// The description of the tool.
    let description = "A probe tool for the tool resolution tests."

    /// Makes a tool with the name `name`.
    ///
    /// - Parameter name: The name of the tool.
    init(name: String) {
        self.name = name
    }

    /// Gives the name of the tool.
    ///
    /// - Parameter arguments: The arguments, which the tool ignores.
    /// - Returns: The name of the tool.
    func call(arguments: Arguments) async throws -> String {
        name
    }
}
