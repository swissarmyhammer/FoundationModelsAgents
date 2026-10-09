import Marketplace

/// The text and the path of one agent file of a live suite.
///
/// Each live agent has a short body with one clear instruction, for example
/// "answer with the word X". A small real model then does the same thing on
/// each run, and a test can assert on that word.
enum LiveAgentFile {
    /// The line that opens and closes a frontmatter.
    private static let frontmatterFence = "---"

    /// Gives the frontmatter line that removes the catalog tools
    /// `toolNames`.
    ///
    /// An agent with no `tools` field gets each tool of the catalog, but not
    /// the `agents` tool. A small model then can call a catalog tool that
    /// the test did not ask for, for example wait in a tool that holds its
    /// call.
    ///
    /// - Parameter toolNames: The names of the catalog tools to remove.
    /// - Returns: The `disallowedTools` line.
    static func disallowedTools(_ toolNames: [String]) -> String {
        "disallowedTools: " + toolNames.joined(separator: ", ")
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

    /// Gives the path of the document of the agent `id`, relative to the
    /// layer root. The parts are the constants that the library reads.
    ///
    /// - Parameter id: The id of the agent: the name of its folder.
    /// - Returns: `agents/<id>/AGENT.md`.
    static func path(of id: String) -> String {
        "\(MarketplaceLayer.agentsDirectoryName)/\(id)/\(MarketplaceLayer.agentDocumentName)"
    }

    /// Gives the text of one agent file.
    ///
    /// - Parameters:
    ///   - id: The id of the agent: the folder name and the `name` field.
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
