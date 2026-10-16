import Foundation

/// The paths and the texts of the agent-folder layout that the agent-folder
/// tests write.
///
/// An agent-folder source is a folder of agent folders. It has no `agents/`
/// level: each `<root>/<id>/AGENT.md` is one agent, and `<root>/AGENT.md` is
/// the default agent.
enum AgentFolderFixture {
    /// The fixed id of the agent that the root `AGENT.md` gives.
    static let defaultAgentID = "default"

    /// The id of the agent that most rows write.
    static let helperID = "helper"

    /// The description of each agent that a row writes.
    static let description = "An agent of an agent-folder test."

    /// The display name of the default agent. It is not a valid id.
    static let displayName = "My Assistant"

    /// The name of the partial that an including body names.
    static let partialName = "house-rules.md"

    /// The name of the folder that holds the partials.
    static let partialsFolderName = "_partials"

    /// The suffix of the placeholder names that a sync engine writes in the
    /// placeholder rows.
    static let placeholderSuffix = ".icloud"

    /// The placeholder of an agent document before the sync engine downloads
    /// it.
    static let documentPlaceholderName = ".\(AgentDocumentPath.documentName)\(placeholderSuffix)"

    /// Gives the path of the document of `id`, relative to the source root.
    ///
    /// - Parameter id: The id of the agent: the name of its folder.
    /// - Returns: `<id>/AGENT.md`.
    static func documentPath(of id: String) -> String {
        "\(id)/\(AgentDocumentPath.documentName)"
    }

    /// Gives the path of a partial in `folder`, relative to the source root.
    ///
    /// - Parameter folder: The folder that holds `_partials/`, or `nil` for
    ///   the source root.
    /// - Returns: `[<folder>/]_partials/house-rules.md`.
    static func partialPath(in folder: String?) -> String {
        let partial = "\(partialsFolderName)/\(partialName)"
        return folder.map { "\($0)/\(partial)" } ?? partial
    }

    /// The body of each agent file that does not name a body.
    static let body = "You are an agent of a test."

    /// Gives the text of a valid agent file.
    ///
    /// This is the one source of the text of a valid agent file for each test
    /// suite that writes one with only `name`, `description`, and a body.
    ///
    /// - Parameters:
    ///   - name: The value of the `name` key.
    ///   - description: The value of the `description` key. The default is
    ///     ``description``.
    ///   - body: The body of the file. The default is ``body``.
    /// - Returns: The text of the file.
    static func agentText(
        name: String, description: String = AgentFolderFixture.description, body: String = AgentFolderFixture.body
    ) -> String {
        """
        ---
        name: \(name)
        description: \(description)
        ---

        \(body)
        """
    }

    /// Gives the text of a valid agent file whose body includes the partial
    /// `partialName`.
    ///
    /// - Parameter name: The value of the `name` key.
    /// - Returns: The text of the file.
    static func includingAgentText(name: String) -> String {
        agentText(name: name, body: "{% include \"\(partialName)\" %}")
    }
}
