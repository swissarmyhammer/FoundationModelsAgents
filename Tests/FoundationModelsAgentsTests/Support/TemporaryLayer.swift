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
        DotfolderStack.Layer(source: .project, root: root)
    }

    /// Makes an empty layer root.
    ///
    /// - Returns: The new layer.
    /// - Throws: The error of the file system when it cannot make the folder.
    static func makeEmpty() throws -> TemporaryLayer {
        let container = try makeContainer()
        let root = container.appendingPathComponent("layer", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return TemporaryLayer(container: container, root: root)
    }

    /// Makes a copy of the layer root at `source`.
    ///
    /// - Parameter source: The layer root to copy, for example
    ///   `FixtureLibrary.defaultsDirectory`.
    /// - Returns: The new layer, which holds the same files as `source`.
    /// - Throws: The error of the file system when it cannot copy a file.
    static func copy(of source: URL) throws -> TemporaryLayer {
        let container = try makeContainer()
        let root = container.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        try FileManager.default.copyItem(at: source, to: root)
        return TemporaryLayer(container: container, root: root)
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
