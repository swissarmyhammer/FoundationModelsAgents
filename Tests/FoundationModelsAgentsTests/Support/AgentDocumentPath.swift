/// The path of the document of an agent in a layer, as the tests write it:
/// `agents/<id>/AGENT.md`.
///
/// The parts are literal text and not the constants of the library. Thus a
/// test that writes an agent with this helper also checks the folder layout
/// that the library reads.
enum AgentDocumentPath {
    /// The name of the document in each agent folder.
    static let documentName = "AGENT.md"

    /// The folder of the layer root that holds the agent folders.
    static let agentsFolderName = "agents"

    /// Gives the path of the document of the agent `id`, relative to a layer
    /// root.
    ///
    /// - Parameter id: The id of the agent: the name of its folder.
    /// - Returns: `agents/<id>/AGENT.md`.
    static func of(_ id: String) -> String {
        "\(agentsFolderName)/\(id)/\(documentName)"
    }
}
