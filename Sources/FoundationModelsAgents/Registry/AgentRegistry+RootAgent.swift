import Foundation
import FoundationModelsExtras
import Marketplace

/// The result of the read of the root `AGENT.md` of one folder.
///
/// ``AgentRegistry/rootAgent(in:id:)`` gives it.
public struct RootAgentLoad: Sendable {
    /// The agent of the folder, or `nil` when the folder has no root
    /// `AGENT.md`, or when the read or the rule table skipped it.
    public let definition: AgentDefinition?

    /// The diagnostics of the read and of the rule table, in order. Empty
    /// when the folder has no root `AGENT.md`.
    public let diagnostics: [AgentDiagnostic]
}

extension AgentRegistry {
    /// The position of the one layer of a root agent read.
    private static let rootAgentLayerIndex = 0

    /// Reads the root `AGENT.md` of one folder as an agent, with no registry
    /// and no catalog.
    ///
    /// A folder with an `AGENT.md` at its root is an agent (D71). The read
    /// uses the folder as a local layer with the source `project`, with the
    /// same coordinated read and the same parser as the catalog build. It
    /// reads only `<folder>/AGENT.md`. It does not read `<folder>/<id>/AGENT.md`
    /// or `<folder>/agents/`.
    ///
    /// The definition gets the id of the call. The default is
    /// ``AgentCatalog/defaultAgentID``, as for the root `AGENT.md` of a local
    /// layer. A host that reads the folder `Agents/<name>/` gives `<name>`,
    /// thus the id is the same as the catalog id of that agent (D70).
    ///
    /// ``AgentRunner/sessionAgentInstructions(for:)`` renders the definition,
    /// also when no layer of a registry holds the folder.
    ///
    /// - Parameters:
    ///   - folder: The folder whose root `AGENT.md` to read.
    ///   - id: The id of the agent. The default is
    ///     ``AgentCatalog/defaultAgentID``.
    /// - Returns: The definition with no diagnostic for a valid file. No
    ///   definition and no diagnostic when the folder has no `AGENT.md`. No
    ///   definition and the diagnostics of the file for a file that is not
    ///   valid, or for a placeholder of a sync engine. No definition and one
    ///   `invalidID` diagnostic for an id that is not valid.
    public static func rootAgent(in folder: URL, id: String = AgentCatalog.defaultAgentID) -> RootAgentLoad {
        let layer = AgentCatalogLayer(layer: DotfolderStack.Layer(source: .project, root: folder), layout: .local)
        guard AgentDefinitionRules.isValidID(id) else {
            return invalidRootAgentID(id, in: folder)
        }
        guard let copy = AgentFolderFormScan.rootCopy(of: id, in: layer.layer, at: rootAgentLayerIndex) else {
            return RootAgentLoad(definition: nil, diagnostics: [])
        }
        return AgentCatalogBuilder.loadRootCopy(copy, of: layer)
    }

    /// Gives the load of a root agent read with an id that is not valid.
    ///
    /// - Parameters:
    ///   - id: The id of the call.
    ///   - folder: The folder of the read.
    /// - Returns: No definition, and one `invalidID` diagnostic about
    ///   `<folder>/AGENT.md`.
    private static func invalidRootAgentID(_ id: String, in folder: URL) -> RootAgentLoad {
        let provenance = AgentDiagnostic.Provenance(
            layerIndex: rootAgentLayerIndex, layerRoot: folder,
            url: folder.appendingPathComponent(MarketplaceLayer.agentDocumentName))
        return RootAgentLoad(
            definition: nil,
            diagnostics: [AgentDefinitionRules.invalidIDFinding(id).diagnostic(agent: nil, provenance: provenance)])
    }
}
