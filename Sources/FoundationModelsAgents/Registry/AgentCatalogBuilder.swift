import Foundation
import FoundationModelsExtras
import Marketplace
import Synchronization

/// Builds one `AgentCatalog` from the marketplace layers and the local
/// layers (plan.md §4.1, §4.3 step 1, §6.1).
///
/// The stack of Extras does each read, and `FrontmatterDocumentStack` does
/// each split. `AgentFrontmatter.decode` decodes the frontmatter, and
/// `AgentDefinition.init` applies the rule table. Thus this type opens no
/// file of its own.
enum AgentCatalogBuilder {
    /// The suffix of an agent file.
    static let fileSuffix = ".md"

    /// Builds the catalog of the marketplace layers and the local layers.
    ///
    /// The layers are `marketplace[0] < … < marketplace[n] < local layers`
    /// (plan.md §4.1). An agent file is a `.md` file directly in `agents/`
    /// of the combined view: a file in a child folder of `agents/` is not
    /// read. The file name is the id. The highest layer that holds a path
    /// wins it, and each lower copy gives one advisory on the diagnostics of
    /// the winner. A bad file does not stop a good file next to it. A
    /// definition from a marketplace layer keeps that layer and its
    /// provenance.
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
        let loads = agentFiles(in: plain).map { file in
            let marketplaceLayer =
                marketplaceLayers.indices.contains(file.winnerIndex) ? marketplaceLayers[file.winnerIndex] : nil
            return load(
                file, marketplaceLayer: marketplaceLayer, documents: documents, decodeFailures: decodeFailures)
        }
        return AgentCatalog(
            definitions: loads.compactMap(\.definition), diagnostics: loads.flatMap(\.diagnostics))
    }

    /// The text of the advisory for a lower copy of an agent file that a
    /// higher layer hides.
    ///
    /// - Parameters:
    ///   - url: The URL of the hidden copy.
    ///   - layerIndex: The position of the layer of the hidden copy.
    /// - Returns: The message.
    static func hiddenCopyMessage(url: URL, layerIndex: Int) -> String {
        "the copy at \(url.path) in layer \(layerIndex) is hidden by this higher copy"
    }

    /// One agent file of the combined view: the id, the path, and the layers
    /// that hold a copy of the path.
    private struct AgentFile {
        /// The file name with no `.md`.
        let id: String

        /// The path of the file relative to a layer root:
        /// `agents/<id>.md`.
        let path: String

        /// The position of the layer that wins the path.
        let winnerIndex: Int

        /// The position of each lower layer that holds a copy of the path,
        /// lowest first.
        let hiddenIndices: [Int]
    }

    /// The result of the load of one agent file.
    private struct AgentFileLoad {
        /// The agent, or `nil` when the file was skipped.
        let definition: AgentDefinition?

        /// The diagnostics of the file, in order.
        let diagnostics: [AgentDiagnostic]
    }

    /// Finds each agent file of the combined view, sorted by id.
    ///
    /// A name that no single layer holds when this type looks at the layers
    /// one by one is left out. That occurs only when the file went away
    /// between the two reads; the next build reads the folder again.
    ///
    /// - Parameter plain: The stack of the layers.
    /// - Returns: The agent files.
    private static func agentFiles(in plain: DotfolderStack) -> [AgentFile] {
        let folder = MarketplaceLayer.agentsDirectoryName
        return plain.enumerate(folder, suffix: fileSuffix).keys.sorted().compactMap { id in
            let path = "\(folder)/\(id)\(fileSuffix)"
            let indices = layerIndices(holding: path, in: plain.layers)
            return indices.last.map { winnerIndex in
                AgentFile(id: id, path: path, winnerIndex: winnerIndex, hiddenIndices: Array(indices.dropLast()))
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

    /// Loads one agent file: the decode failures, the rule table, and one
    /// advisory for each hidden copy.
    ///
    /// - Parameters:
    ///   - file: The agent file.
    ///   - marketplaceLayer: The marketplace layer that wins the file, or
    ///     `nil` when a local layer wins it.
    ///   - documents: The document stack of all the layers.
    ///   - decodeFailures: The log that `documents` reports each decode
    ///     failure to.
    /// - Returns: The agent, or `nil`, with the diagnostics of the file.
    private static func load(
        _ file: AgentFile,
        marketplaceLayer: MarketplaceLayer?,
        documents: FrontmatterDocumentStack<DotfolderStack, AgentFrontmatter>,
        decodeFailures: DecodeFailureLog
    ) -> AgentFileLoad {
        let layers = documents.layers
        let provenance = AgentDiagnostic.Provenance(
            layerIndex: file.winnerIndex, layerRoot: layers[file.winnerIndex].root,
            url: layers[file.winnerIndex].root.appendingPathComponent(file.path),
            marketplace: marketplaceLayer?.provenance)
        let document = documents.item(at: file.path)
        let agent = AgentDefinitionRules.isValidID(file.id) ? file.id : nil
        var diagnostics = decodeFailures.removeAll().map { failure in
            AgentDiagnostic(severity: .advisory, agent: agent, provenance: provenance, message: failure.message)
        }
        let definition = AgentDefinition(
            id: file.id, document: document, provenance: provenance, marketplaceLayer: marketplaceLayer,
            diagnostics: &diagnostics)
        diagnostics += file.hiddenIndices.map { index in
            let hiddenURL = layers[index].root.appendingPathComponent(file.path)
            return AgentDiagnostic(
                severity: .advisory, agent: agent, provenance: provenance,
                message: hiddenCopyMessage(url: hiddenURL, layerIndex: index))
        }
        return AgentFileLoad(definition: definition, diagnostics: diagnostics)
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
