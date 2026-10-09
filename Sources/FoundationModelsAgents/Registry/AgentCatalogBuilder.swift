import Foundation
import FoundationModelsExtras
import Marketplace
import Synchronization

/// Builds one `AgentCatalog` from the marketplace layers and the local
/// layers.
///
/// The stack of Extras does each read, and `FrontmatterDocumentStack` does
/// each split. `AgentFrontmatter.decode` decodes the frontmatter, and
/// `AgentDefinition.init` applies the rule table. Thus this type opens no
/// file of its own.
enum AgentCatalogBuilder {
    /// The suffix of an agent file of the old format: `agents/<id>.md`.
    static let oldFormatSuffix = ".md"

    /// Builds the catalog of the marketplace layers and the local layers.
    ///
    /// The layers are `marketplace[0] < … < marketplace[n] < local layers`.
    /// An agent is a child folder of `agents/` of the combined view that
    /// holds `AGENT.md`: `agents/<id>/AGENT.md`. The folder name is the id,
    /// and the other files of the folder are the resources of the agent. The
    /// highest layer that holds the document wins it, and each lower copy
    /// gives one advisory on the diagnostics of the winner. A bad agent does
    /// not stop a good agent next to it. A definition from a marketplace
    /// layer keeps that layer and its provenance.
    ///
    /// A `.md` file directly in `agents/` has the old format. It gives no
    /// agent. Each such file of each layer gives one warning, after the
    /// diagnostics of the agent folders.
    ///
    /// - Parameters:
    ///   - marketplaceLayers: The marketplace layers, lowest precedence
    ///     first.
    ///   - localLayers: The local layers, lowest precedence first.
    /// - Returns: The catalog.
    static func build(
        marketplaceLayers: [MarketplaceLayer], localLayers: [DotfolderStack.Layer]
    ) -> AgentCatalog {
        let plain = DotfolderStack(layers: marketplaceLayers.map(\.layer) + localLayers)
        let decodeFailures = DecodeFailureLog()
        let documents = FrontmatterDocumentStack(
            base: plain, decode: AgentFrontmatter.decode, onDiagnostic: decodeFailures.record)
        let loads = agentFolders(in: plain).map { folder in
            load(
                folder, marketplaceLayer: marketplaceLayer(at: folder.winnerIndex, in: marketplaceLayers),
                documents: documents, decodeFailures: decodeFailures)
        }
        let oldFormatWarnings = oldFormatWarnings(in: plain.layers, marketplaceLayers: marketplaceLayers)
        return AgentCatalog(
            definitions: loads.compactMap(\.definition),
            diagnostics: loads.flatMap(\.diagnostics) + oldFormatWarnings)
    }

    /// The path of the document of an agent, relative to a layer root.
    ///
    /// - Parameter id: The id of the agent: the name of its folder.
    /// - Returns: `agents/<id>/AGENT.md`.
    static func documentPath(of id: String) -> String {
        "\(MarketplaceLayer.agentsDirectoryName)/\(id)/\(MarketplaceLayer.agentDocumentName)"
    }

    /// The text of the advisory for a lower copy of an agent document that a
    /// higher layer hides.
    ///
    /// - Parameters:
    ///   - url: The URL of the hidden copy.
    ///   - layerIndex: The position of the layer of the hidden copy.
    /// - Returns: The message.
    static func hiddenCopyMessage(url: URL, layerIndex: Int) -> String {
        "the copy at \(url.path) in layer \(layerIndex) is hidden by this higher copy"
    }

    /// One agent folder of the combined view: the id, the path of the
    /// document, and the layers that hold a copy of the document.
    private struct AgentFolder {
        /// The folder name: the id of the agent.
        let id: String

        /// The path of the document relative to a layer root:
        /// `agents/<id>/AGENT.md`.
        let path: String

        /// The position of the layer that wins the document.
        let winnerIndex: Int

        /// The position of each lower layer that holds a copy of the
        /// document, lowest first.
        let hiddenIndices: [Int]
    }

    /// One agent file of the old format in one layer.
    private struct OldFormatFile {
        /// The file name with no `.md`.
        let name: String

        /// The position of the layer that holds the file.
        let layerIndex: Int

        /// The URL of the file.
        let url: URL
    }

    /// The result of the load of one agent folder.
    private struct AgentFolderLoad {
        /// The agent, or `nil` when the document was skipped.
        let definition: AgentDefinition?

        /// The diagnostics of the document, in order.
        let diagnostics: [AgentDiagnostic]
    }

    /// Finds each agent folder of the combined view, sorted by id.
    ///
    /// A child folder of `agents/` that no layer fills with `AGENT.md` is not
    /// an agent, for example `agents/_partials/`. A name that no single layer
    /// holds when this type looks at the layers one by one is left out. That
    /// occurs only when the document went away between the two reads; the
    /// next build reads the folder again.
    ///
    /// - Parameter plain: The stack of the layers.
    /// - Returns: The agent folders.
    private static func agentFolders(in plain: DotfolderStack) -> [AgentFolder] {
        plain.childDirectories(of: MarketplaceLayer.agentsDirectoryName).keys.sorted().compactMap { id in
            let path = documentPath(of: id)
            let indices = layerIndices(holding: path, in: plain.layers)
            return indices.last.map { winnerIndex in
                AgentFolder(id: id, path: path, winnerIndex: winnerIndex, hiddenIndices: Array(indices.dropLast()))
            }
        }
    }

    /// Finds the position of each layer that holds `path`.
    ///
    /// - Parameters:
    ///   - path: A path relative to a layer root.
    ///   - layers: The layers, lowest precedence first.
    /// - Returns: The positions, lowest first.
    private static func layerIndices(holding path: String, in layers: [DotfolderStack.Layer]) -> [Int] {
        layers.indices.filter { index in
            DotfolderStack(layers: [layers[index]]).exists(path)
        }
    }

    /// Gives the marketplace layer at a position of the combined layer list.
    ///
    /// - Parameters:
    ///   - layerIndex: A position in the combined layer list.
    ///   - marketplaceLayers: The marketplace layers, lowest precedence
    ///     first. They are the first positions of the combined list.
    /// - Returns: The marketplace layer, or `nil` for a local layer.
    private static func marketplaceLayer(at layerIndex: Int, in marketplaceLayers: [MarketplaceLayer])
        -> MarketplaceLayer?
    {
        marketplaceLayers.indices.contains(layerIndex) ? marketplaceLayers[layerIndex] : nil
    }

    /// Loads one agent folder: the decode failures, the rule table, and one
    /// advisory for each hidden copy.
    ///
    /// - Parameters:
    ///   - folder: The agent folder.
    ///   - marketplaceLayer: The marketplace layer that wins the folder, or
    ///     `nil` when a local layer wins it.
    ///   - documents: The document stack of all the layers.
    ///   - decodeFailures: The log that `documents` reports each decode
    ///     failure to.
    /// - Returns: The agent, or `nil`, with the diagnostics of the document.
    private static func load(
        _ folder: AgentFolder,
        marketplaceLayer: MarketplaceLayer?,
        documents: FrontmatterDocumentStack<DotfolderStack, AgentFrontmatter>,
        decodeFailures: DecodeFailureLog
    ) -> AgentFolderLoad {
        let layers = documents.layers
        let provenance = AgentDiagnostic.Provenance(
            layerIndex: folder.winnerIndex, layerRoot: layers[folder.winnerIndex].root,
            url: layers[folder.winnerIndex].root.appendingPathComponent(folder.path),
            marketplace: marketplaceLayer?.provenance)
        let document = documents.item(at: folder.path)
        let agent = AgentDefinitionRules.isValidID(folder.id) ? folder.id : nil
        var diagnostics = decodeFailures.removeAll().map { failure in
            AgentDiagnostic(severity: .advisory, agent: agent, provenance: provenance, message: failure.message)
        }
        let definition = AgentDefinition(
            id: folder.id, document: document, provenance: provenance, marketplaceLayer: marketplaceLayer,
            diagnostics: &diagnostics)
        diagnostics += folder.hiddenIndices.map { index in
            let hiddenURL = layers[index].root.appendingPathComponent(folder.path)
            return AgentDiagnostic(
                severity: .advisory, agent: agent, provenance: provenance,
                message: hiddenCopyMessage(url: hiddenURL, layerIndex: index))
        }
        return AgentFolderLoad(definition: definition, diagnostics: diagnostics)
    }

    /// Gives one warning for each agent file of the old format: a `.md` file
    /// directly in `agents/` of a layer.
    ///
    /// The search looks at each layer by itself, thus a copy in a lower
    /// layer also gives its warning. The search lists the files and reads no
    /// text.
    ///
    /// - Parameters:
    ///   - layers: The layers, lowest precedence first.
    ///   - marketplaceLayers: The marketplace layers: the first positions of
    ///     `layers`.
    /// - Returns: The warnings, sorted by file name, then by layer position.
    private static func oldFormatWarnings(
        in layers: [DotfolderStack.Layer], marketplaceLayers: [MarketplaceLayer]
    ) -> [AgentDiagnostic] {
        let files = layers.indices.flatMap { index in oldFormatFiles(in: layers[index], at: index) }
        return files.sorted { ($0.name, $0.layerIndex) < ($1.name, $1.layerIndex) }.map { file in
            let provenance = AgentDiagnostic.Provenance(
                layerIndex: file.layerIndex, layerRoot: layers[file.layerIndex].root, url: file.url,
                marketplace: marketplaceLayer(at: file.layerIndex, in: marketplaceLayers)?.provenance)
            let agent = AgentDefinitionRules.isValidID(file.name) ? file.name : nil
            return AgentDefinitionRules.oldFormatFinding(file.name).diagnostic(agent: agent, provenance: provenance)
        }
    }

    /// Finds each agent file of the old format in one layer.
    ///
    /// - Parameters:
    ///   - layer: The layer.
    ///   - layerIndex: The position of the layer in the combined layer list.
    /// - Returns: Each `.md` file directly in `agents/` of the layer.
    private static func oldFormatFiles(in layer: DotfolderStack.Layer, at layerIndex: Int) -> [OldFormatFile] {
        DotfolderStack(layers: [layer]).urls(MarketplaceLayer.agentsDirectoryName).compactMap { path, file in
            guard !path.contains("/"), path.hasSuffix(oldFormatSuffix) else { return nil }
            let name = String(path.dropLast(oldFormatSuffix.count))
            return OldFormatFile(name: name, layerIndex: layerIndex, url: file.url)
        }
    }
}

/// The decode failures that a `FrontmatterDocumentStack` reports while the
/// builder reads one file.
///
/// The hook of the stack is a `@Sendable` closure, thus the log keeps the
/// failures behind a `Mutex`.
private final class DecodeFailureLog: Sendable {
    /// The failures since the last `removeAll()`.
    private let failures = Mutex<[DotfolderStack.Diagnostic]>([])

    /// Adds one failure. The document stack calls this as its hook.
    ///
    /// - Parameter failure: The failure.
    func record(_ failure: DotfolderStack.Diagnostic) {
        failures.withLock { $0.append(failure) }
    }

    /// Takes each failure out of the log.
    ///
    /// - Returns: The failures since the last call, in order.
    func removeAll() -> [DotfolderStack.Diagnostic] {
        failures.withLock { current in
            defer { current = [] }
            return current
        }
    }
}
