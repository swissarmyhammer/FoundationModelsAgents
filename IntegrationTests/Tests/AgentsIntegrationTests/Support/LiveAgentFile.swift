/// The text and the path of one agent file of a live suite.
///
/// Each live agent has a short body with one clear instruction, for example
/// "answer with the word X". A small real model then does the same thing on
/// each run, and a test can assert on that word.
enum LiveAgentFile {
    /// The name of the folder that holds the agent files of a layer.
    static let agentsFolderName = "agents"

    /// The `disallowedTools` entry that removes the `agents` tool.
    private static let agentsToolEntry = "Agent"

    /// The line that opens and closes a frontmatter.
    private static let frontmatterFence = "---"

    /// Gives the frontmatter line that removes the `agents` tool and the
    /// catalog tools `toolNames`.
    ///
    /// An agent with no `tools` field gets each tool of the catalog and the
    /// `agents` tool. A small model then can call a tool that the test did
    /// not ask for, for example start an agent, or wait in a tool that holds
    /// its call.
    ///
    /// - Parameter toolNames: The names of the catalog tools to remove.
    /// - Returns: The `disallowedTools` line.
    static func disallowedTools(_ toolNames: [String] = []) -> String {
        "disallowedTools: " + ([agentsToolEntry] + toolNames).joined(separator: ", ")
    }

    /// Gives the body that tells the model to answer with one word.
    ///
    /// - Parameter word: The word.
    /// - Returns: The body.
    static func answerBody(word: String) -> String {
        "Answer each prompt with the single word \(word). Write no other text."
    }

    /// Gives the body that tells the model to call a tool and to answer with
    /// the word that the tool gives.
    ///
    /// Only the tool knows the word, thus the model must call the tool.
    ///
    /// - Parameter toolName: The name of the tool.
    /// - Returns: The body.
    static func toolWordBody(toolName: String) -> String {
        "Call the tool \"\(toolName)\" one time. Then answer with the single word that the tool gives. "
            + "Write no other text."
    }

    /// Gives the path of the file of the agent `id`, relative to the layer
    /// root.
    ///
    /// - Parameter id: The id of the agent.
    /// - Returns: `agents/<id>.md`.
    static func path(of id: String) -> String {
        "\(agentsFolderName)/\(id).md"
    }

    /// Gives the text of one agent file.
    ///
    /// - Parameters:
    ///   - id: The id of the agent: the file name and the `name` field.
    ///   - description: The `description` field.
    ///   - fields: More frontmatter lines, for example `model: flash` or
    ///     `tools: hold`.
    ///   - body: The body: the instructions of the agent.
    /// - Returns: The frontmatter and the body.
    static func text(id: String, description: String, fields: [String] = [], body: String) -> String {
        let frontmatter = ["name: \(id)", "description: \(description)"] + fields
        return ([frontmatterFence] + frontmatter + [frontmatterFence, "", body]).joined(separator: "\n")
    }
}
