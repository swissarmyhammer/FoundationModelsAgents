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

    /// The text of the skip for an agent document that the build cannot read
    /// yet: a placeholder, or a file that does not read as text.
    static let notLocalMessage =
        "the agent document is not local yet; the next build loads it when the file is local"

    /// The text of the skip for an agent whose winning copy has
    /// `enabled: false`.
    static let disabledMessage = "the agent is turned off ('\(FrontmatterEnablement.key): false')"

    /// Builds the catalog of the marketplace layers and the local layers.
    ///
    /// The layers are `marketplace[0] < … < marketplace[n]`, then the local
    /// layers in the order of the stack of the host, for example `defaults <
    /// user < project` (`AgentCatalogLayer.ordered`). Each layer holds an
    /// agent as `agents/<id>/AGENT.md`. A local layer also holds an agent as
    /// `<id>/AGENT.md`, and its root `AGENT.md` is the agent `default`. The
    /// folder name is the id, and the other files of the folder are the
    /// resources of the agent. The highest layer that holds a copy of an id
    /// wins it, and each lower copy gives one advisory on the diagnostics of
    /// the winner. In one layer, `<id>/AGENT.md` wins over
    /// `agents/<id>/AGENT.md`. A bad agent does not stop a good agent next to
    /// it. A definition from a marketplace layer keeps that layer and its
    /// provenance.
    ///
    /// A `.md` file directly in `agents/` of a layer has the old format. It
    /// gives no agent. Each such file of each layer gives one warning, after
    /// the diagnostics of the agent folders.
    ///
    /// - Parameters:
    ///   - marketplaceLayers: The marketplace layers, lowest precedence
    ///     first.
    ///   - localLayers: The local layers, lowest precedence first.
    /// - Returns: The catalog.
    static func build(
        marketplaceLayers: [MarketplaceLayer], localLayers: [DotfolderStack.Layer]
    ) -> AgentCatalog {
        let layers = AgentCatalogLayer.ordered(marketplaceLayers: marketplaceLayers, localLayers: localLayers)
        let scans = layers.indices.map { index in AgentLayerScan(layers[index], at: index) }
        let loads = foldersByID(in: scans).map { folder in
            load(
                folder, layers: layers,
                marketplaceLayer: marketplaceLayer(at: folder.winner.layerIndex, in: marketplaceLayers))
        }
        let oldFormatWarnings = oldFormatWarnings(in: layers, marketplaceLayers: marketplaceLayers)
        return AgentCatalog(
            definitions: loads.compactMap(\.definition),
            diagnostics: loads.flatMap(\.diagnostics) + oldFormatWarnings)
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

    /// The text of the warning for `<root>/default/AGENT.md` of a local layer
    /// that also holds a root `AGENT.md`.
    static let hiddenDefaultFolderMessage =
        "the folder '\(AgentCatalog.defaultAgentID)/' is hidden by the root \(MarketplaceLayer.agentDocumentName) "
            + "of the same layer; the root \(MarketplaceLayer.agentDocumentName) is the default agent"

    /// One agent of the combined view: the winning copy, and the copies that
    /// it hides.
    private struct AgentFolder {
        /// The copy in the highest layer that holds the id.
        let winner: AgentCopy

        /// Each lower copy of the id, lowest first.
        let hiddenCopies: [AgentCopy]

        /// Each `<root>/default/AGENT.md` that a root `AGENT.md` hides, in
        /// layer order. Empty for each id other than `default`.
        let hiddenDefaultFolders: [AgentCopy]
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

    /// Groups the copies of the scans by id, sorted by id.
    ///
    /// - Parameter scans: The scan of each layer, lowest precedence first.
    /// - Returns: One agent folder for each id that a layer holds.
    private static func foldersByID(in scans: [AgentLayerScan]) -> [AgentFolder] {
        let copiesByID = Dictionary(grouping: scans.flatMap(\.copies), by: \.id)
        let hiddenDefaultFoldersByID = Dictionary(grouping: scans.flatMap(\.hiddenDefaultFolders), by: \.id)
        return copiesByID.keys.sorted().compactMap { id in
            let copies = copiesByID[id] ?? []
            return copies.last.map { winner in
                AgentFolder(
                    winner: winner, hiddenCopies: Array(copies.dropLast()),
                    hiddenDefaultFolders: hiddenDefaultFoldersByID[id] ?? [])
            }
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

    /// Gives the URL of the file of a copy.
    ///
    /// - Parameters:
    ///   - copy: The copy.
    ///   - layers: The layers of the build.
    /// - Returns: The layer root with the path of the copy.
    private static func url(of copy: AgentCopy, in layers: [AgentCatalogLayer]) -> URL {
        layers[copy.layerIndex].layer.root.appendingPathComponent(copy.path)
    }

    /// Loads one agent folder: the read of the winning copy, the rule table,
    /// one advisory for each hidden copy, and one warning for each hidden
    /// `default/` folder.
    ///
    /// - Parameters:
    ///   - folder: The agent folder.
    ///   - layers: The layers of the build.
    ///   - marketplaceLayer: The marketplace layer that wins the folder, or
    ///     `nil` when a local layer wins it.
    /// - Returns: The agent, or `nil`, with the diagnostics of the document.
    private static func load(
        _ folder: AgentFolder, layers: [AgentCatalogLayer], marketplaceLayer: MarketplaceLayer?
    ) -> AgentFolderLoad {
        let winner = folder.winner
        let provenance = AgentDiagnostic.Provenance(
            layerIndex: winner.layerIndex, layerRoot: layers[winner.layerIndex].layer.root,
            url: url(of: winner, in: layers), marketplace: marketplaceLayer?.provenance)
        let agent = AgentDefinitionRules.isValidID(winner.id) ? winner.id : nil
        let read = readWinner(
            winner, of: layers[winner.layerIndex], provenance: provenance, marketplaceLayer: marketplaceLayer)
        let hiddenCopyAdvisories = folder.hiddenCopies.map { copy in
            AgentDiagnostic(
                severity: .advisory, agent: agent, provenance: provenance,
                message: hiddenCopyMessage(url: url(of: copy, in: layers), layerIndex: copy.layerIndex))
        }
        let hiddenDefaultFolderWarnings = folder.hiddenDefaultFolders.map { copy in
            AgentDiagnostic(
                severity: .warning, agent: agent,
                provenance: AgentDiagnostic.Provenance(
                    layerIndex: copy.layerIndex, layerRoot: layers[copy.layerIndex].layer.root,
                    url: url(of: copy, in: layers)),
                message: hiddenDefaultFolderMessage)
        }
        return AgentFolderLoad(
            definition: read.definition,
            diagnostics: read.diagnostics + hiddenCopyAdvisories + hiddenDefaultFolderWarnings)
    }

    /// Reads the winning copy of one agent, and applies the rule table.
    ///
    /// A placeholder, and a document of the agent folder form that the build
    /// cannot read, give one `skip` with `notLocalMessage`. A sync engine then
    /// downloads the file, and the next build loads it. A coordinated read
    /// that fails gives one `skip` with `coordinationFailedMessage(_:)`, which
    /// states the cause of the failure.
    ///
    /// - Parameters:
    ///   - winner: The winning copy.
    ///   - layer: The layer of the winning copy.
    ///   - provenance: The file of the agent.
    ///   - marketplaceLayer: The marketplace layer that gave the file, or
    ///     `nil` for a local layer.
    /// - Returns: The agent, or `nil`, with the diagnostics of the read and
    ///   of the rule table.
    private static func readWinner(
        _ winner: AgentCopy, of layer: AgentCatalogLayer, provenance: AgentDiagnostic.Provenance,
        marketplaceLayer: MarketplaceLayer?
    ) -> AgentFolderLoad {
        let agent = AgentDefinitionRules.isValidID(winner.id) ? winner.id : nil
        let decodeFailures = DecodeFailureLog()
        let document: Located<FrontmatterDocument<AgentFrontmatter>>?
        switch readDocument(of: winner, in: layer, at: provenance.url, decodeFailures: decodeFailures) {
        case .failure(let failure):
            return skip(agent: agent, provenance: provenance, message: coordinationFailedMessage(failure))
        case .success(let read):
            document = read
        }
        guard document != nil || !winner.kind.isInAgentFolderForm else {
            return skip(agent: agent, provenance: provenance, message: notLocalMessage)
        }
        if let enablement = document?.value.enablement, !enablement.isEnabled {
            return skip(agent: agent, provenance: provenance, message: offMessage(enablement))
        }
        var diagnostics = decodeFailures.removeAll().map { failure in
            AgentDiagnostic(severity: .advisory, agent: agent, provenance: provenance, message: failure.message)
        }
        let definition = AgentDefinition(
            id: winner.id, document: document, provenance: provenance, marketplaceLayer: marketplaceLayer,
            kind: winner.kind, diagnostics: &diagnostics)
        return AgentFolderLoad(definition: definition, diagnostics: diagnostics)
    }

    /// Gives the text of the skip for an agent that is off.
    ///
    /// - Parameter enablement: The enablement of the winning copy. It is not
    ///   `.enabled`.
    /// - Returns: ``disabledMessage`` for `enabled: false`, or the message of
    ///   FoundationModelsExtras for a value that is not `true` or `false`.
    private static func offMessage(_ enablement: FrontmatterEnablement) -> String {
        if case .invalid(let message) = enablement {
            return message
        }
        return disabledMessage
    }

    /// A coordinated read that the file coordinator could not do.
    struct CoordinatedReadFailure: Error {
        /// The description of the error of the file coordinator.
        let reason: String
    }

    /// The text of the skip for an agent document that a coordinated read
    /// could not get.
    ///
    /// - Parameter failure: The failure of the coordinated read.
    /// - Returns: The message, with the reason of `failure`.
    static func coordinationFailedMessage(_ failure: CoordinatedReadFailure) -> String {
        "the coordinated read of the agent document failed: \(failure.reason)"
    }

    /// Reads the document of a copy from a stack of its layer only.
    ///
    /// A placeholder gives no document. The read of a document of the agent
    /// folder form is coordinated (`NSFileCoordinator`), thus a sync engine
    /// can give the current file. The kind of the copy decides this, not the
    /// layer: a local layer holds documents of both forms.
    ///
    /// - Parameters:
    ///   - copy: The copy.
    ///   - layer: The layer of the copy.
    ///   - url: The URL of the file of the copy.
    ///   - decodeFailures: The log that gets each decode failure of the read.
    /// - Returns: The document, or `nil`, or the failure of the coordinated
    ///   read.
    private static func readDocument(
        of copy: AgentCopy, in layer: AgentCatalogLayer, at url: URL, decodeFailures: DecodeFailureLog
    ) -> Result<Located<FrontmatterDocument<AgentFrontmatter>>?, CoordinatedReadFailure> {
        let documents = FrontmatterDocumentStack(
            base: DotfolderStack(layers: [layer.layer]), decode: AgentFrontmatter.decode,
            onDiagnostic: decodeFailures.record)
        return switch (copy.state, copy.kind.isInAgentFolderForm) {
        case (.notLocal, _): .success(nil)
        case (.document, false): .success(documents.item(at: copy.path))
        case (.document, true): coordinatedRead(of: url) { documents.item(at: copy.path) }
        }
    }

    /// Gives the load of an agent that the build skips.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent, or `nil` when the id is not valid.
    ///   - provenance: The file of the agent.
    ///   - message: The reason for the skip.
    /// - Returns: No agent, and one `skip` diagnostic.
    private static func skip(
        agent: String?, provenance: AgentDiagnostic.Provenance, message: String
    ) -> AgentFolderLoad {
        AgentFolderLoad(
            definition: nil,
            diagnostics: [AgentDiagnostic(severity: .skip, agent: agent, provenance: provenance, message: message)])
    }

    /// Runs `read` in a coordinated read of the file at `url`.
    ///
    /// A sync engine that presents the file can give the current version
    /// before the read. When the coordination fails, `read` does not run.
    ///
    /// - Parameters:
    ///   - url: The file to read.
    ///   - read: The read. The stack of Extras opens the file in it.
    /// - Returns: What `read` gave, or the failure of the coordination.
    private static func coordinatedRead<Value>(
        of url: URL, _ read: () -> Value?
    ) -> Result<Value?, CoordinatedReadFailure> {
        var value: Value?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url, options: [], error: &coordinationError
        ) { _ in
            value = read()
        }
        if let coordinationError {
            return .failure(CoordinatedReadFailure(reason: coordinationError.localizedDescription))
        }
        return .success(value)
    }

    /// Gives one warning for each agent file of the old format: a `.md` file
    /// directly in `agents/` of a layer.
    ///
    /// The search looks at each layer by itself, thus a copy in a lower
    /// layer also gives its warning. The search lists the files and reads no
    /// text. Each layer reads the dotfolder form `agents/`, thus each layer
    /// can give a warning. A `.md` file of the agent folder form is a
    /// resource, and gives no warning.
    ///
    /// - Parameters:
    ///   - layers: The layers of the build, lowest precedence first.
    ///   - marketplaceLayers: The marketplace layers: the first positions of
    ///     `layers`.
    /// - Returns: The warnings, sorted by file name, then by layer position.
    private static func oldFormatWarnings(
        in layers: [AgentCatalogLayer], marketplaceLayers: [MarketplaceLayer]
    ) -> [AgentDiagnostic] {
        let files = layers.indices.flatMap { index in
            oldFormatFiles(in: layers[index].layer, at: index)
        }
        return files.sorted { ($0.name, $0.layerIndex) < ($1.name, $1.layerIndex) }.map { file in
            let provenance = AgentDiagnostic.Provenance(
                layerIndex: file.layerIndex, layerRoot: layers[file.layerIndex].layer.root, url: file.url,
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
