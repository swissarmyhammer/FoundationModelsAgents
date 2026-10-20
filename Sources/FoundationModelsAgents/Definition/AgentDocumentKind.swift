import Marketplace

/// Where an agent document sits in its layer.
///
/// The kind gives the path of the document relative to the layer root, the
/// rule for the `name` key, and the layers that the render of the body reads
/// partials from.
enum AgentDocumentKind: Sendable, Equatable {
    /// `agents/<id>/AGENT.md`: the dotfolder form of a local layer, and the
    /// form of a marketplace layer.
    case agentsFolder

    /// `<id>/AGENT.md`: the agent folder form of a local layer, with no
    /// `agents/` level.
    case agentFolder

    /// `AGENT.md` at the root of a local layer: the default agent.
    case rootDocument

    /// Whether the rule table compares the `name` key with the id.
    ///
    /// The `name` of the root document is a display name, thus the rule
    /// table does not check it.
    var checksName: Bool {
        self != .rootDocument
    }

    /// Whether the document is in the agent folder form of a local layer:
    /// `<id>/AGENT.md`, or the root `AGENT.md`.
    ///
    /// The build reads such a document in a coordinated read, and a
    /// placeholder of it gives the not-local skip. The render of such a
    /// document reads the partials of its own layer only.
    var isInAgentFolderForm: Bool {
        self != .agentsFolder
    }

    /// Gives the path of the document of `id`, relative to the layer root.
    ///
    /// - Parameter id: The id of the agent: the name of its folder.
    /// - Returns: `agents/<id>/AGENT.md`, `<id>/AGENT.md`, or `AGENT.md`.
    func documentPath(of id: String) -> String {
        switch self {
        case .agentsFolder:
            "\(MarketplaceLayer.agentsDirectoryName)/\(id)/\(MarketplaceLayer.agentDocumentName)"
        case .agentFolder:
            "\(id)/\(MarketplaceLayer.agentDocumentName)"
        case .rootDocument:
            MarketplaceLayer.agentDocumentName
        }
    }
}
