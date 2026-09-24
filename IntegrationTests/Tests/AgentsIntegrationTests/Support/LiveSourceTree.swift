import Foundation

/// The agent files of `LiveSourcesTests`: one agent in a local layer, and one
/// agent in a plugin of a small marketplace.
///
/// Each agent answers each prompt with ``answerWord``. Thus a test can see
/// that the real model ran the body of the agent that it started.
///
/// The marketplace tree has the shape of `Examples/agent-library/marketplace`:
/// `.claude-plugin/marketplace.json` names one plugin, and the plugin folder
/// holds `agents/<id>.md`. A test commits the tree to a git repository, or
/// writes it to a folder for a `file://` source.
enum LiveSourceTree {
    /// The word that each agent must answer with.
    static let answerWord = "PINEAPPLE"

    /// The prompt of each live run.
    static let prompt = "Give your answer now."

    /// The id of the agent of the local layer.
    static let localAgentID = "local-echo"

    /// The id of the agent of the marketplace plugin.
    static let pluginAgentID = "plugin-echo"

    /// The name of the one plugin of the marketplace. It is also the alias of
    /// a `file://` source.
    static let pluginName = "live-tools"

    /// The folder of the plugin, relative to the marketplace root.
    static let pluginPath = "plugins/\(pluginName)"

    /// The name of the folder that holds the agent files of a layer.
    private static let agentsFolderName = "agents"

    /// The catalog of the marketplace.
    private static let catalogText = """
        {
          "name": "live-sources",
          "owner": { "name": "swissarmyhammer" },
          "metadata": {
            "description": "The marketplace of the live source tests: one plugin with one agent.",
            "version": "1.0.0"
          },
          "plugins": [
            {
              "name": "\(pluginName)",
              "source": "./\(pluginPath)",
              "strict": false,
              "description": "One agent that answers with one word."
            }
          ]
        }
        """

    /// The files of the local layer, one entry for each path relative to the
    /// layer root.
    static var localLayerFiles: [String: String] {
        ["\(agentsFolderName)/\(localAgentID).md": agentText(id: localAgentID)]
    }

    /// The files of the marketplace, one entry for each path relative to the
    /// marketplace root.
    static var marketplaceFiles: [String: String] {
        [
            ".claude-plugin/marketplace.json": catalogText,
            "\(pluginPath)/\(agentsFolderName)/\(pluginAgentID).md": agentText(id: pluginAgentID)
        ]
    }

    /// Makes a new, empty folder in the temporary directory.
    ///
    /// - Returns: The folder. The caller removes it.
    /// - Throws: The error of the file system.
    static func makeTemporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("agents-live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes each file to a new temporary folder.
    ///
    /// - Parameter files: The text of each file, by its path relative to the
    ///   folder.
    /// - Returns: The folder. The caller removes it.
    /// - Throws: The error of the file system.
    static func writeTemporaryFolder(holding files: [String: String]) throws -> URL {
        let folder = try makeTemporaryFolder()
        for (path, text) in files {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return folder
    }

    /// The text of one agent file.
    ///
    /// - Parameter id: The id of the agent: the file name and the `name`
    ///   field.
    /// - Returns: The frontmatter and the body. The body tells the model to
    ///   answer with ``answerWord``.
    private static func agentText(id: String) -> String {
        """
        ---
        name: \(id)
        description: Answers each prompt with one fixed word, for the live source tests.
        ---

        You are a test agent. Answer each prompt with the single word \(answerWord). \
        Write no other text.
        """
    }
}
