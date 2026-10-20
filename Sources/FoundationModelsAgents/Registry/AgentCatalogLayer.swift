import Foundation
import FoundationModelsExtras
import Marketplace

/// One layer of a catalog build, with the layout of its agent folders.
///
/// A marketplace layer holds its agents in `agents/<id>/AGENT.md` only. A
/// local layer holds its agents in two forms: the dotfolder form
/// `agents/<id>/AGENT.md`, and the agent folder form `<id>/AGENT.md`, where
/// the root `AGENT.md` of the layer is the default agent.
struct AgentCatalogLayer: Sendable {
    /// Where the agent folders of a layer are.
    enum Layout: Sendable, Equatable {
        /// Each agent is `agents/<id>/AGENT.md`. A marketplace layer has this
        /// layout.
        case dotfolder

        /// Each agent is `agents/<id>/AGENT.md` or `<id>/AGENT.md`, and
        /// `AGENT.md` is the default agent. A local layer has this layout.
        case local
    }

    /// The layer.
    let layer: DotfolderStack.Layer

    /// The layout of the agent folders of the layer.
    let layout: Layout

    /// Gives the layers of a build in precedence order, lowest first:
    /// `marketplace[0] < … < marketplace[n]`, then the local layers in the
    /// order of the stack of the host, for example `defaults < user <
    /// project`.
    ///
    /// - Parameters:
    ///   - marketplaceLayers: The marketplace layers, lowest precedence
    ///     first.
    ///   - localLayers: The local layers of the host, lowest precedence
    ///     first.
    /// - Returns: The layers of the build.
    static func ordered(
        marketplaceLayers: [MarketplaceLayer], localLayers: [DotfolderStack.Layer]
    ) -> [AgentCatalogLayer] {
        marketplaceLayers.map { AgentCatalogLayer(layer: $0.layer, layout: .dotfolder) }
            + localLayers.map { AgentCatalogLayer(layer: $0, layout: .local) }
    }
}
