import Foundation
import FoundationModelsExtras
import Marketplace

/// The reason why `AgentWriter` refused or could not do a write.
///
/// Each case has a corrective ``message``. The `agents` tool gives the
/// message to the model, thus the message tells the model what to do next.
enum AgentWriterError: Error, Equatable {
    /// The id is not a valid agent id (`AgentDefinitionRules.isValidID`).
    case invalidID(String)

    /// The id is the name of a folder of the layer layout, for example
    /// `agents` or `skills`.
    case reservedID(String)

    /// The agent exists in the target layer, thus an add cannot write it.
    case alreadyExists(id: String, layer: AgentWriteLayer)

    /// The agent does not exist in the target layer. `existsIn` holds the
    /// source of each local layer where the agent exists, lowest first.
    case notFound(id: String, layer: AgentWriteLayer, existsIn: [DotfolderStack.Source])

    /// The document path is empty, absolute, has a `..` component, goes out
    /// of the agent folder, or goes into the folder of a different item.
    case unsafeDocument(String)

    /// The agent `default` has the layer root as its folder, thus a remove
    /// cannot delete it.
    case cannotRemoveDefault

    /// The stack has no local layer of this source.
    case layerUnavailable(AgentWriteLayer)

    /// The file coordinator could not coordinate the access. The value is the
    /// description of its error.
    case coordinationFailed(String)

    /// The file system refused the write or the delete. The value is the
    /// description of its error.
    case writeFailed(String)

    /// The text for the model: what is wrong, and what to do.
    var message: String {
        switch self {
        case .invalidID(let id):
            "The id '\(id)' is not valid. An agent id has 1 to \(AgentDefinition.idCharacterLimit) characters "
                + "of a-z, 0-9 and '-'. It does not start or end with '-', and it does not contain '--'. "
                + "Use a different id."
        case .reservedID(let id):
            "The id '\(id)' is the name of a folder of the layer layout. Use a different id."
        case .alreadyExists(let id, let layer):
            "The agent '\(id)' exists in the '\(layer.rawValue)' layer. Use 'edit agent' to change it."
        case .notFound(let id, let layer, let existsIn):
            Self.notFoundMessage(id: id, layer: layer, existsIn: existsIn)
        case .unsafeDocument(let document):
            "The document path '\(document)' is not safe. Use a relative path in the agent folder with no '..' "
                + "component, for example '\(MarketplaceLayer.agentDocumentName)' or 'notes/plan.md'. A document "
                + "of the agent '\(AgentCatalog.defaultAgentID)' cannot go into the folder of a different item."
        case .cannotRemoveDefault:
            "You cannot remove the agent '\(AgentCatalog.defaultAgentID)', because its folder is the layer root. "
                + "Use 'edit agent' to change its \(MarketplaceLayer.agentDocumentName)."
        case .layerUnavailable(let layer):
            "The '\(layer.rawValue)' layer is not available here. Use a different layer."
        case .coordinationFailed(let reason):
            "The coordinated access to the file failed: \(reason). Try again."
        case .writeFailed(let reason):
            "The change to the file failed: \(reason). Make sure that the folder is writable, then try again."
        }
    }

    /// Gives the text of `notFound`.
    ///
    /// - Parameters:
    ///   - id: The id of the agent.
    ///   - layer: The target layer.
    ///   - existsIn: The source of each local layer where the agent exists.
    /// - Returns: The text. It names each layer where the agent exists, thus
    ///   the model can select the correct layer or add an override.
    private static func notFoundMessage(
        id: String, layer: AgentWriteLayer, existsIn: [DotfolderStack.Source]
    ) -> String {
        let missing = "The agent '\(id)' does not exist in the '\(layer.rawValue)' layer."
        guard !existsIn.isEmpty else {
            return missing + " Use 'list agents' to see the agents, or use 'add agent' to make it."
        }
        let layers = existsIn.map { "'\($0)'" }.joined(separator: ", ")
        let writable = AgentWriteLayer.allCases.map { "'\($0.rawValue)'" }.joined(separator: " or ")
        return missing + " It exists in these layers: \(layers). To change a copy in the \(writable) layer, "
            + "use that layer. To override a copy, use 'add agent' with the layer '\(layer.rawValue)'."
    }
}
