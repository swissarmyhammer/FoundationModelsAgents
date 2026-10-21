import Foundation
import FoundationModelsExtras

/// One layer root in a new folder under the temporary directory of the
/// process.
///
/// A test that must change the files of a layer, for example to delete them
/// after the registry built its catalog, uses a copy and never the fixture
/// library itself. Each layer has its own folder, thus tests that run in
/// parallel do not share files. The test calls `delete()` in a `defer`.
struct TemporaryLayer {
    /// The folder that this helper made. It holds `root`.
    let container: URL

    /// The root of the layer.
    let root: URL

    /// The layer over `root`, with the untrusted source of a project layer.
    var layer: DotfolderStack.Layer {
        layer(source: .project)
    }

    /// The layer over `root`, with the source `user`. A test uses it as the
    /// root settings folder of a host, for example the synced `Agents/`
    /// folder of an app.
    var userLayer: DotfolderStack.Layer {
        layer(source: .user)
    }

    /// Makes the layer over `root` with the source that the test gives.
    ///
    /// This is the one place that makes a layer of this helper.
    ///
    /// - Parameter source: The source of the layer, for example `.project`
    ///   or `.user`.
    /// - Returns: The layer over `root` with `source`.
    func layer(source: DotfolderStack.Source) -> DotfolderStack.Layer {
        DotfolderStack.Layer(source: source, root: root)
    }

    /// Makes an empty layer root.
    ///
    /// - Returns: The new layer.
    /// - Throws: The error of the file system when it cannot make the folder.
    static func makeEmpty() throws -> TemporaryLayer {
        try make(rootNamed: emptyRootName) { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }

    /// Makes a layer root that holds `files`.
    ///
    /// - Parameter files: The text of each file, by its path relative to the
    ///   root, for example `agents/helper/AGENT.md`.
    /// - Returns: The new layer.
    /// - Throws: The error of the file system when it cannot make the folder
    ///   or write a file.
    static func make(holding files: [String: String]) throws -> TemporaryLayer {
        let layer = try makeEmpty()
        for (path, text) in files {
            try layer.write(text, at: path)
        }
        return layer
    }

    /// Makes a layer root that holds one valid agent at
    /// `agents/<id>/AGENT.md`.
    ///
    /// - Parameter id: The id of the agent: the name of its folder.
    /// - Returns: The new layer.
    /// - Throws: The error of the file system when it cannot make the folder
    ///   or write the file.
    static func make(holdingAgent id: String) throws -> TemporaryLayer {
        try make(holding: [AgentDocumentPath.of(id): AgentFolderFixture.agentText(name: id)])
    }

    /// Makes a copy of the layer root at `source`.
    ///
    /// - Parameter source: The layer root to copy, for example
    ///   `FixtureLibrary.defaultsDirectory`.
    /// - Returns: The new layer, which holds the same files as `source`.
    /// - Throws: The error of the file system when it cannot copy a file.
    static func copy(of source: URL) throws -> TemporaryLayer {
        try make(rootNamed: source.lastPathComponent) { root in
            try FileManager.default.copyItem(at: source, to: root)
        }
    }

    /// Writes `text` to the file at `relativePath`, and makes each folder
    /// that the path needs.
    ///
    /// - Parameters:
    ///   - text: The text of the file.
    ///   - relativePath: The path of the file relative to `root`.
    /// - Throws: The error of the file system when it cannot write the file.
    func write(_ text: String, at relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Removes the file or the folder at `relativePath`.
    ///
    /// - Parameter relativePath: The path relative to `root`.
    /// - Throws: The error of the file system when it cannot remove the item.
    func remove(_ relativePath: String) throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent(relativePath))
    }

    /// Removes `container` and all the files in it.
    ///
    /// - Throws: The error of the file system when it cannot remove the
    ///   folder.
    func delete() throws {
        try FileManager.default.removeItem(at: container)
    }

    /// The folder name of the root that `makeEmpty()` makes.
    private static let emptyRootName = "layer"

    /// Makes a new container, and a root in it that `fill` makes.
    ///
    /// This is the one place that makes a `TemporaryLayer`.
    ///
    /// - Parameters:
    ///   - name: The folder name of the root in the container.
    ///   - fill: Makes the root folder at the URL that it gets, for example
    ///     as an empty folder or as a copy of a fixture.
    /// - Returns: The new layer.
    /// - Throws: The error of the file system when it cannot make the
    ///   container, or the error of `fill`.
    private static func make(
        rootNamed name: String, filling fill: (URL) throws -> Void
    ) throws -> TemporaryLayer {
        let container = try makeContainer()
        let root = container.appendingPathComponent(name, isDirectory: true)
        try fill(root)
        return TemporaryLayer(container: container, root: root)
    }

    /// Makes a new, empty folder under the temporary directory.
    ///
    /// - Returns: The URL of the folder.
    /// - Throws: The error of the file system when it cannot make the folder.
    private static func makeContainer() throws -> URL {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemporaryLayer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return container
    }
}
