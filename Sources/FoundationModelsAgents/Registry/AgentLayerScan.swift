import Foundation
import FoundationModelsExtras
import Marketplace

/// One copy of an agent in one layer: the id, the layer, the file, and
/// whether the file is local.
struct AgentCopy: Sendable, Equatable {
    /// Whether the build can read the file of a copy.
    enum State: Sendable, Equatable {
        /// The file is the agent document.
        case document

        /// The file is the placeholder of a document that a sync engine did
        /// not make local yet.
        case notLocal
    }

    /// The id of the agent.
    let id: String

    /// The position of the layer in the combined layer list.
    let layerIndex: Int

    /// The path of the file of the copy, relative to the layer root: the
    /// agent document, or its placeholder.
    let path: String

    /// Where the document sits in its layer.
    let kind: AgentDocumentKind

    /// Whether the build can read the file.
    let state: State
}

/// The agent copies of one layer.
///
/// The scan lists the files of the layer and reads no text. Each layer gives
/// each `agents/<id>/AGENT.md`. A local layer also gives each `<id>/AGENT.md`
/// of the agent folder form, its root `AGENT.md` as the agent `default`, and
/// each placeholder of one of these documents.
///
/// In one layer, a copy of the agent folder form wins over a copy of the
/// same id in `agents/`. Thus the copies of the agent folder form come after
/// the copies of `agents/`: the builder takes the last copy of an id as the
/// winner, and each earlier copy gives the hidden-copy advisory.
struct AgentLayerScan: Sendable {
    /// The copies of the layer, the copies of `agents/` first.
    let copies: [AgentCopy]

    /// Each `<root>/default/AGENT.md` of a local layer that the root
    /// `AGENT.md` of the same layer hides.
    let hiddenDefaultFolders: [AgentCopy]

    /// Scans one layer.
    ///
    /// - Parameters:
    ///   - layer: The layer and its layout.
    ///   - layerIndex: The position of the layer in the combined layer list.
    init(_ layer: AgentCatalogLayer, at layerIndex: Int) {
        let dotfolderCopies = Self.dotfolderCopies(in: layer.layer, at: layerIndex)
        switch layer.layout {
        case .dotfolder:
            copies = dotfolderCopies
            hiddenDefaultFolders = []
        case .local:
            let scan = AgentFolderFormScan(layer.layer, at: layerIndex)
            let root = scan.rootCopy
            let isHiddenByRoot = { (copy: AgentCopy) in root != nil && copy.id == AgentCatalog.defaultAgentID }
            copies = dotfolderCopies + (root.map { [$0] } ?? []) + scan.folderCopies.filter { !isHiddenByRoot($0) }
            hiddenDefaultFolders = scan.folderCopies.filter(isHiddenByRoot)
        }
    }

    /// Finds each `agents/<id>/AGENT.md` of a layer.
    ///
    /// A child folder of `agents/` that holds no `AGENT.md` is not an agent,
    /// for example `agents/_partials/`.
    ///
    /// - Parameters:
    ///   - layer: The layer.
    ///   - layerIndex: The position of the layer in the combined layer list.
    /// - Returns: The copies, in no order.
    private static func dotfolderCopies(in layer: DotfolderStack.Layer, at layerIndex: Int) -> [AgentCopy] {
        let single = DotfolderStack(layers: [layer])
        return single.childDirectories(of: MarketplaceLayer.agentsDirectoryName).keys.compactMap { id in
            let path = AgentDocumentKind.agentsFolder.documentPath(of: id)
            guard single.exists(path) else { return nil }
            return AgentCopy(id: id, layerIndex: layerIndex, path: path, kind: .agentsFolder, state: .document)
        }
    }
}

/// The files of the agent folder form of one local layer, as copies of
/// agents.
///
/// The scan makes one walk of the files of the layer with
/// `DotfolderStack.urls(_:)`, which lists the hidden files too. It reads no
/// text. A layer root that does not exist gives no copy.
///
/// A child folder of the layer root whose name is not a valid agent id is a
/// settings folder, for example `_skills/`, `_rules/`, `_partials/`, or
/// `.git/`. It gives no copy, thus also no diagnostic.
///
/// A sync engine keeps each folder, and writes a placeholder only in place of
/// a file. Thus a hidden file directly in the layer root is never an agent
/// folder. For example, `.env.local` gives no agent `env`.
///
/// ``rootCopy(of:in:at:)`` gives the root copy of one layer with an id that
/// the caller gives. `AgentRegistry.rootAgent(in:id:)` uses it, thus the
/// read of the root `AGENT.md` of one folder uses the same names as the
/// build.
struct AgentFolderFormScan {
    /// The copy of the default agent: the root `AGENT.md`, or its
    /// placeholder.
    let rootCopy: AgentCopy?

    /// One copy for each agent folder `<id>/` with a valid id that holds
    /// `AGENT.md` or its placeholder.
    let folderCopies: [AgentCopy]

    /// Scans the agent folder form of one local layer.
    ///
    /// - Parameters:
    ///   - layer: The local layer.
    ///   - layerIndex: The position of the layer in the combined layer list.
    init(_ layer: DotfolderStack.Layer, at layerIndex: Int) {
        let paths = Self.paths(in: layer)
        let folderEntries = paths.compactMap(Self.folderEntry).filter { AgentDefinitionRules.isValidID($0.folder) }
        let namesByFolder = Dictionary(grouping: folderEntries, by: \.folder).mapValues { $0.map(\.name) }
        rootCopy = Self.rootCopy(of: AgentCatalog.defaultAgentID, names: Self.rootNames(in: paths), at: layerIndex)
        folderCopies = namesByFolder.compactMap { folder, names in
            Self.copy(of: folder, kind: .agentFolder, names: names, folder: folder, layerIndex: layerIndex)
        }
    }

    /// Gives the copy of the root `AGENT.md` of one layer, or of its
    /// placeholder, with the id `id`.
    ///
    /// The scan reads no text. It does not look at `<id>/AGENT.md` or at
    /// `agents/`.
    ///
    /// - Parameters:
    ///   - id: The id that the copy gets.
    ///   - layer: The layer whose root holds the document.
    ///   - layerIndex: The position of the layer in its layer list.
    /// - Returns: The copy, or `nil` when the root holds neither `AGENT.md`
    ///   nor its placeholder.
    static func rootCopy(of id: String, in layer: DotfolderStack.Layer, at layerIndex: Int) -> AgentCopy? {
        rootCopy(of: id, names: rootNames(in: paths(in: layer)), at: layerIndex)
    }

    /// The character between the components of a path.
    private static let separator = "/"

    /// Lists the path of each file of a layer, relative to its root. The
    /// list holds the hidden files too.
    ///
    /// - Parameter layer: The layer.
    /// - Returns: The paths, in no order.
    private static func paths(in layer: DotfolderStack.Layer) -> [String] {
        Array(DotfolderStack(layers: [layer]).urls().keys)
    }

    /// Gives the names of the files directly in the layer root.
    ///
    /// - Parameter paths: The file paths of the layer, relative to its root.
    /// - Returns: Each path with no separator.
    private static func rootNames(in paths: [String]) -> [String] {
        paths.filter { !$0.contains(separator) }
    }

    /// Gives the copy of the root document from the names of the files
    /// directly in the layer root.
    ///
    /// - Parameters:
    ///   - id: The id that the copy gets.
    ///   - names: The names of the files directly in the layer root.
    ///   - layerIndex: The position of the layer in its layer list.
    /// - Returns: The copy, or `nil` when the root holds neither the
    ///   document nor its placeholder.
    private static func rootCopy(of id: String, names: [String], at layerIndex: Int) -> AgentCopy? {
        copy(of: id, kind: .rootDocument, names: names, folder: nil, layerIndex: layerIndex)
    }

    /// The count of the components of the path of a file directly in an
    /// agent folder: the folder and the file name.
    private static let folderEntryComponentCount = 2

    /// Splits the path of a file directly in a child folder of the root.
    ///
    /// - Parameter path: A file path relative to the layer root.
    /// - Returns: The folder and the file name, or `nil` for a file at the
    ///   root or deeper in a folder.
    private static func folderEntry(_ path: String) -> (folder: String, name: String)? {
        let components = path.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        guard components.count == folderEntryComponentCount else { return nil }
        return (components[0], components[1])
    }

    /// Gives the copy of one agent from the file names of its folder.
    ///
    /// Only the exact name `AGENT.md` is the document. Only a name
    /// `.AGENT.md.<suffix>` is its placeholder. Each other name, for example
    /// a conflict copy `AGENT 2.md` or a hidden file `.AGENT.md`, is a
    /// resource.
    ///
    /// - Parameters:
    ///   - id: The id of the agent.
    ///   - kind: Where the document sits in the layer.
    ///   - names: The names of the files directly in the folder.
    ///   - folder: The folder relative to the layer root, or `nil` for the
    ///     root.
    ///   - layerIndex: The position of the layer in the combined layer list.
    /// - Returns: The copy, or `nil` when the folder holds neither the
    ///   document nor its placeholder.
    private static func copy(
        of id: String, kind: AgentDocumentKind, names: [String], folder: String?, layerIndex: Int
    ) -> AgentCopy? {
        guard !names.contains(MarketplaceLayer.agentDocumentName) else {
            return AgentCopy(
                id: id, layerIndex: layerIndex, path: kind.documentPath(of: id), kind: kind, state: .document)
        }
        let prefix = folder.map { "\($0)\(separator)" } ?? ""
        return names.sorted().first(where: AgentPlaceholderName.standsForDocument).map { name in
            AgentCopy(id: id, layerIndex: layerIndex, path: prefix + name, kind: kind, state: .notLocal)
        }
    }
}

/// The rule for the hidden names that a sync engine writes in place of a
/// file that is not local yet.
///
/// The rule uses the names only. It names no sync service and calls no API
/// of one.
private enum AgentPlaceholderName {
    /// The first character of a hidden name, and the character between the
    /// document name and the suffix of a placeholder name.
    private static let dot = "."

    /// The start of each placeholder name of an agent document:
    /// `.AGENT.md.`.
    private static let documentPrefix = dot + MarketplaceLayer.agentDocumentName + dot

    /// Tells whether `name` is a placeholder of an agent document: the name
    /// `.AGENT.md.<suffix>`, with a suffix that is not empty.
    ///
    /// - Parameter name: A file name.
    /// - Returns: `true` for a placeholder of `AGENT.md`.
    static func standsForDocument(_ name: String) -> Bool {
        name.hasPrefix(documentPrefix) && name.count > documentPrefix.count
    }
}
