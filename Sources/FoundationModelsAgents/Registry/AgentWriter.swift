import Foundation
import FoundationModelsExtras
import Marketplace

/// The local layer that a write of `AgentWriter` goes to.
///
/// The names and the values are the same as the `layer` option of the
/// `skills` tool. The default of each operation is ``user``.
public enum AgentWriteLayer: String, Sendable, CaseIterable {
    /// The user layer: the root settings folder of the host, for example the
    /// synced `Agents/` folder of the app.
    case user

    /// The project layer: `<working folder of the session>/.agents/`.
    case project

    /// The source of the layers of the stack that a write to this layer can
    /// go to.
    var source: DotfolderStack.Source {
        switch self {
        case .user: .user
        case .project: .project
        }
    }
}

/// Adds, edits and removes agent folders in the user layer or the project
/// layer of an `AgentRegistry`.
///
/// The target layer of a write is the highest local layer whose source is
/// the source of the `AgentWriteLayer`. A `.defaults` layer and a
/// marketplace layer are read-only, thus a write never goes to them.
///
/// The writer finds the agents of a layer with `AgentLayerScan`, the scan of
/// the catalog build. Thus an agent exists for the writer when it exists for
/// the catalog: `<root>/<id>/AGENT.md` or `<root>/agents/<id>/AGENT.md` (or
/// the placeholder of that document). The agent `default` exists when the
/// root `AGENT.md` of the layer exists, and its folder is the layer root.
///
/// Each write and each delete is coordinated (`NSFileCoordinator`), thus a
/// sync engine sees the change. The writer does not reload: the caller calls
/// `AgentRegistry.reload()` after a write.
struct AgentWriter: Sendable {
    /// The ids that are folder names of the layer layout. A write or a
    /// delete of such a folder damages other items of the layer.
    static let reservedIDs: Set<String> = [MarketplaceLayer.agentsDirectoryName, "skills", "rules", "partials"]

    /// The child folders of a layer root that hold items that are not the
    /// agent `default`. A document of `default` cannot go into them.
    static let otherItemFolderNames: Set<String> = [
        MarketplaceLayer.agentsDirectoryName, "_skills", "_rules", MarketplaceLayout.defaultPartialsDirectoryName
    ]

    /// The default document of an edit: the agent document.
    static let agentDocument = MarketplaceLayer.agentDocumentName

    /// The path component that names the parent folder.
    private static let parentComponent = ".."

    /// The character between the components of a path.
    private static let separator: Character = "/"

    /// The local layers of the registry, lowest precedence first.
    let localLayers: [DotfolderStack.Layer]

    /// Makes a writer over local layers.
    ///
    /// - Parameter localLayers: The local layers, lowest precedence first.
    init(localLayers: [DotfolderStack.Layer]) {
        self.localLayers = localLayers
    }

    /// Makes a writer over the local layers of a registry.
    ///
    /// - Parameter registry: The registry. The writer uses its
    ///   `localLayers`.
    init(registry: AgentRegistry) {
        self.init(localLayers: registry.localLayers)
    }

    /// Writes a new agent: `<root>/<id>/AGENT.md`, or the root `AGENT.md` for
    /// the agent `default`.
    ///
    /// An agent of the same id in a lower layer is not an error: the new
    /// agent overrides it.
    ///
    /// - Parameters:
    ///   - id: The id of the new agent.
    ///   - content: The full text of the agent document.
    ///   - layer: The target layer.
    /// - Returns: The URL of the document that the add wrote.
    /// - Throws: `invalidID`, `reservedID`, `layerUnavailable`,
    ///   `alreadyExists`, `coordinationFailed` or `writeFailed`.
    func add(id: String, content: String, layer: AgentWriteLayer = .user) throws(AgentWriterError) -> [URL] {
        try Self.checkWritable(id)
        let target = try targetLayer(layer)
        guard copies(of: id, in: scan(of: target)).isEmpty else {
            throw .alreadyExists(id: id, layer: layer)
        }
        let kind: AgentDocumentKind = id == AgentCatalog.defaultAgentID ? .rootDocument : .agentFolder
        let url = target.root.appending(path: kind.documentPath(of: id), directoryHint: .notDirectory)
        try AgentFileCoordination.write(content, to: url)
        return [url]
    }

    /// Replaces the full text of one document of an agent.
    ///
    /// When the layer holds both forms of the agent, the edit writes the form
    /// that the catalog reads: `<root>/<id>/`. The edit makes the folders of
    /// a new document.
    ///
    /// - Parameters:
    ///   - id: The id of the agent.
    ///   - document: The path of the document, relative to the agent folder.
    ///   - content: The full text of the document.
    ///   - layer: The target layer.
    /// - Returns: The URL of the document that the edit wrote.
    /// - Throws: `invalidID`, `reservedID`, `layerUnavailable`, `notFound`,
    ///   `unsafeDocument`, `coordinationFailed` or `writeFailed`.
    func edit(
        id: String, document: String = agentDocument, content: String, layer: AgentWriteLayer = .user
    ) throws(AgentWriterError) -> [URL] {
        try Self.checkWritable(id)
        let target = try targetLayer(layer)
        let layerScan = scan(of: target)
        guard let copy = copies(of: id, in: layerScan).last else {
            throw notFound(id, in: layer)
        }
        let folder = Self.folder(of: copy, in: target)
        try Self.checkDocument(document, in: folder)
        if id == AgentCatalog.defaultAgentID {
            try Self.checkDefaultDocument(document, besides: layerScan)
        }
        let url = folder.appending(path: document, directoryHint: .notDirectory)
        try AgentFileCoordination.write(content, to: url)
        return [url]
    }

    /// Deletes each form of an agent in the target layer: `<root>/<id>/` and
    /// `<root>/agents/<id>/`. Thus no copy of that layer stays in the
    /// catalog. A copy in a different layer stays.
    ///
    /// - Parameters:
    ///   - id: The id of the agent.
    ///   - layer: The target layer.
    /// - Returns: The URL of each folder that the remove deleted.
    /// - Throws: `invalidID`, `reservedID`, `cannotRemoveDefault`,
    ///   `layerUnavailable`, `notFound`, `coordinationFailed` or
    ///   `writeFailed`.
    func remove(id: String, layer: AgentWriteLayer = .user) throws(AgentWriterError) -> [URL] {
        try Self.checkWritable(id)
        guard id != AgentCatalog.defaultAgentID else {
            throw .cannotRemoveDefault
        }
        let target = try targetLayer(layer)
        let folders = copies(of: id, in: scan(of: target)).map { Self.folder(of: $0, in: target) }
        guard !folders.isEmpty else {
            throw notFound(id, in: layer)
        }
        for folder in folders {
            try AgentFileCoordination.delete(folder)
        }
        return folders
    }

    /// Refuses an id that the id rule refuses, and a reserved id.
    ///
    /// - Parameter id: The id of the agent.
    /// - Throws: `invalidID` or `reservedID`.
    private static func checkWritable(_ id: String) throws(AgentWriterError) {
        guard AgentDefinitionRules.isValidID(id) else {
            throw .invalidID(id)
        }
        guard !reservedIDs.contains(id) else {
            throw .reservedID(id)
        }
    }

    /// Gives the target layer of a write.
    ///
    /// - Parameter layer: The write layer.
    /// - Returns: The highest local layer with the source of `layer`.
    /// - Throws: `layerUnavailable` when no local layer has that source.
    private func targetLayer(_ layer: AgentWriteLayer) throws(AgentWriterError) -> DotfolderStack.Layer {
        guard let target = localLayers.last(where: { $0.source == layer.source }) else {
            throw .layerUnavailable(layer)
        }
        return target
    }

    /// Scans one local layer with the rule of the catalog build.
    ///
    /// - Parameter layer: The local layer.
    /// - Returns: The scan.
    private func scan(of layer: DotfolderStack.Layer) -> AgentLayerScan {
        AgentLayerScan(AgentCatalogLayer(layer: layer, layout: .local), at: 0)
    }

    /// Gives the copies of an agent in one scan, in the order of the scan.
    ///
    /// The last copy is the copy that the catalog reads. For the agent
    /// `default`, only the root `AGENT.md` counts.
    ///
    /// - Parameters:
    ///   - id: The id of the agent.
    ///   - scan: The scan of one layer.
    /// - Returns: The copies.
    private func copies(of id: String, in scan: AgentLayerScan) -> [AgentCopy] {
        let isDefault = id == AgentCatalog.defaultAgentID
        return scan.copies.filter { $0.id == id && ($0.kind == .rootDocument) == isDefault }
    }

    /// Gives the `notFound` error with each local layer where the agent
    /// exists.
    ///
    /// - Parameters:
    ///   - id: The id of the agent.
    ///   - layer: The target layer.
    /// - Returns: The error.
    private func notFound(_ id: String, in layer: AgentWriteLayer) -> AgentWriterError {
        let existsIn = localLayers.filter { !copies(of: id, in: scan(of: $0)).isEmpty }.map(\.source)
        return .notFound(id: id, layer: layer, existsIn: existsIn)
    }

    /// Gives the folder of a copy: the layer root for the root `AGENT.md`,
    /// `<root>/<id>/`, or `<root>/agents/<id>/`.
    ///
    /// - Parameters:
    ///   - copy: The copy.
    ///   - layer: The layer of the copy.
    /// - Returns: The URL of the folder.
    private static func folder(of copy: AgentCopy, in layer: DotfolderStack.Layer) -> URL {
        let components = copy.kind.documentPath(of: copy.id).split(separator: separator).dropLast()
        guard !components.isEmpty else {
            return layer.root
        }
        return layer.root.appending(path: components.joined(separator: String(separator)), directoryHint: .isDirectory)
    }

    /// Refuses a document path that is not a safe path in the agent folder.
    ///
    /// - Parameters:
    ///   - document: The path of the document, relative to the agent folder.
    ///   - folder: The agent folder.
    /// - Throws: `unsafeDocument` for an empty or absolute path, a path with
    ///   a `..` component, or a path that goes out of `folder`, also through
    ///   a symbolic link.
    private static func checkDocument(_ document: String, in folder: URL) throws(AgentWriterError) {
        let components = document.split(separator: separator, omittingEmptySubsequences: false)
        guard !document.isEmpty, document.first != separator, !components.contains(Substring(parentComponent)),
            PathConfinement.isConfined(folder.appending(path: document), to: folder)
        else {
            throw .unsafeDocument(document)
        }
    }

    /// Refuses a document of the agent `default` whose first component is a
    /// child folder of the layer root that holds a different item.
    ///
    /// - Parameters:
    ///   - document: The path of the document, relative to the layer root.
    ///   - scan: The scan of the layer.
    /// - Throws: `unsafeDocument` when the first component is the folder of
    ///   an agent, `agents`, `_skills`, `_rules` or `_partials`.
    private static func checkDefaultDocument(_ document: String, besides scan: AgentLayerScan) throws(AgentWriterError) {
        let agentFolderIDs = (scan.copies + scan.hiddenDefaultFolders).filter { $0.kind == .agentFolder }.map(\.id)
        let otherItems = otherItemFolderNames.union(agentFolderIDs)
        let first = document.split(separator: separator).first.map(String.init) ?? document
        guard !otherItems.contains(first) else {
            throw .unsafeDocument(document)
        }
    }
}

/// The coordinated writes and deletes of `AgentWriter`.
///
/// Each access uses `NSFileCoordinator`, in the same form as the
/// coordinated read of `AgentCatalogBuilder`.
private enum AgentFileCoordination {
    /// Writes `content` to the file at `url`, and makes each folder that the
    /// path needs.
    ///
    /// - Parameters:
    ///   - content: The full text of the file.
    ///   - url: The file.
    /// - Throws: `coordinationFailed` or `writeFailed`.
    static func write(_ content: String, to url: URL) throws(AgentWriterError) {
        try coordinate(url, options: .forReplacing) { coordinated in
            try FileManager.default.createDirectory(
                at: coordinated.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: coordinated, options: .atomic)
        }
    }

    /// Deletes the file or the folder at `url`.
    ///
    /// - Parameter url: The file or the folder.
    /// - Throws: `coordinationFailed` or `writeFailed`.
    static func delete(_ url: URL) throws(AgentWriterError) {
        try coordinate(url, options: .forDeleting) { coordinated in
            try FileManager.default.removeItem(at: coordinated)
        }
    }

    /// Runs `access` in a coordinated write of the item at `url`.
    ///
    /// - Parameters:
    ///   - url: The item.
    ///   - options: The options of the coordinated write.
    ///   - access: The change. It gets the URL that the coordinator gives.
    /// - Throws: `coordinationFailed` when the coordination fails, then
    ///   `access` does not run. `writeFailed` when `access` throws.
    private static func coordinate(
        _ url: URL, options: NSFileCoordinator.WritingOptions, _ access: (URL) throws -> Void
    ) throws(AgentWriterError) {
        var coordinationError: NSError?
        var accessError: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: options, error: &coordinationError
        ) { coordinated in
            do {
                try access(coordinated)
            } catch {
                accessError = error
            }
        }
        if let coordinationError {
            throw .coordinationFailed(coordinationError.localizedDescription)
        }
        if let accessError {
            throw .writeFailed(accessError.localizedDescription)
        }
    }
}
