import Foundation
import FoundationModelsExtras
import Marketplace

/// One layer of a catalog build, with the layout of its agent folders.
///
/// A dotfolder layer and a marketplace layer hold their agents in
/// `agents/<id>/AGENT.md`. An agent-folder source has no `agents/` level: it
/// holds `<id>/AGENT.md`, and its root `AGENT.md` is the default agent.
struct AgentCatalogLayer: Sendable {
    /// Where the agent folders of a layer are.
    enum Layout: Sendable, Equatable {
        /// Each agent is `agents/<id>/AGENT.md`.
        case dotfolder

        /// Each agent is `<id>/AGENT.md`, and `AGENT.md` is the default
        /// agent.
        case agentFolder
    }

    /// The layer.
    let layer: DotfolderStack.Layer

    /// The layout of the agent folders of the layer.
    let layout: Layout

    /// Gives the layers of a build in precedence order, lowest first:
    /// `marketplace[0] < … < marketplace[n] < defaults < user < agent folders
    /// < project`.
    ///
    /// The agent folders go directly below the first `project` layer of
    /// `localLayers`. A local layer that a host puts above the project
    /// layer stays above it. With no `project` layer, the agent folders are
    /// the highest layers.
    ///
    /// - Parameters:
    ///   - marketplaceLayers: The marketplace layers, lowest precedence
    ///     first.
    ///   - localLayers: The local layers of the host, lowest precedence
    ///     first.
    ///   - agentFolderLayers: The layers of the agent-folder sources, in the
    ///     order of the URLs that the host gave. A later URL wins a path.
    /// - Returns: The layers of the build.
    static func ordered(
        marketplaceLayers: [MarketplaceLayer], localLayers: [DotfolderStack.Layer],
        agentFolderLayers: [DotfolderStack.Layer]
    ) -> [AgentCatalogLayer] {
        let projectStart = localLayers.firstIndex { $0.source == .project } ?? localLayers.endIndex
        let belowAgentFolders = marketplaceLayers.map(\.layer) + localLayers[..<projectStart]
        return belowAgentFolders.map(dotfolder) + agentFolderLayers.map(agentFolder)
            + localLayers[projectStart...].map(dotfolder)
    }

    /// Gives the layer of an agent-folder source at `url`.
    ///
    /// The source is `user`: its documents render untrusted, and it is not a
    /// marketplace layer.
    ///
    /// - Parameter url: The root of the source.
    /// - Returns: The layer.
    static func agentFolderLayer(at url: URL) -> DotfolderStack.Layer {
        DotfolderStack.Layer(source: .user, root: url)
    }

    /// Wraps a layer whose agents are in `agents/`.
    ///
    /// - Parameter layer: The layer.
    /// - Returns: The layer with the `dotfolder` layout.
    private static func dotfolder(_ layer: DotfolderStack.Layer) -> AgentCatalogLayer {
        AgentCatalogLayer(layer: layer, layout: .dotfolder)
    }

    /// Wraps the layer of an agent-folder source.
    ///
    /// - Parameter layer: The layer.
    /// - Returns: The layer with the `agentFolder` layout.
    private static func agentFolder(_ layer: DotfolderStack.Layer) -> AgentCatalogLayer {
        AgentCatalogLayer(layer: layer, layout: .agentFolder)
    }
}
