import Foundation
import FoundationModelsExtras
import Marketplace

/// The fixture library of the example: `Examples/agent-library` (plan.md §13).
///
/// Each URL comes from the `#filePath` of this file or from the caller. Thus
/// the example never reads the real home directory or `$XDG_CONFIG_HOME`.
enum AgentsDemoLibrary {
    /// The dotfolder name of the stack. The project layer is
    /// `project/.agents/`.
    static let dotfolderName = "agents"

    /// The plugins of the fixture marketplace. Each one is a `file://`
    /// source, and the alias of the source is the plugin name.
    static let marketplacePlugins = ["code-tools", "docs-tools"]

    /// The document that marks a skill folder in a marketplace tree.
    static let skillDocumentName = "SKILL.md"

    /// The root of the fixture library: `Examples/agent-library`.
    static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("agent-library", isDirectory: true)
    }

    /// The cache folder of the marketplace store of the example. A folder
    /// source keeps no cache entry, thus the store only reads this folder.
    static var cacheDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("agents-demo-marketplace", isDirectory: true)
    }

    /// The project folder of a library: the working directory of its stack
    /// and of the runs of the example. Its project layer is
    /// `project/.agents/`.
    ///
    /// - Parameter libraryRoot: The root of the library.
    /// - Returns: `<libraryRoot>/project`.
    static func projectDirectory(libraryRoot: URL) -> URL {
        libraryRoot.appendingPathComponent("project", isDirectory: true)
    }

    /// The local layer stack over a library: `defaults < user < project`.
    ///
    /// The environment is empty. Thus `AGENTS_DEFAULTS_DIR` and
    /// `XDG_CONFIG_HOME` cannot move a layer onto a real host directory.
    ///
    /// - Parameter libraryRoot: The root of the library, for example `root`
    ///   or a copy of it.
    /// - Returns: The stack, lowest layer first.
    static func stack(libraryRoot: URL) -> DotfolderStack {
        DotfolderStack(
            name: dotfolderName,
            workingDirectory: projectDirectory(libraryRoot: libraryRoot),
            defaultsDirectory: libraryRoot.appendingPathComponent("defaults", isDirectory: true),
            userDirectory: libraryRoot.appendingPathComponent("user", isDirectory: true),
            environment: [:])
    }

    /// Makes a marketplace store over the fixture marketplace of a library.
    ///
    /// Each plugin of `marketplace/plugins/` is one `file://` source with the
    /// `path` of the plugin folder. A folder source is its own layer root:
    /// the store makes no copy and fetches nothing, thus its layer is there
    /// when `init` returns.
    ///
    /// - Parameters:
    ///   - libraryRoot: The root of the library.
    ///   - cacheDirectory: The cache folder of the store.
    /// - Returns: The store. Its layers hold `agents/*.md` of each plugin.
    static func marketplaceStore(libraryRoot: URL, cacheDirectory: URL) -> MarketplaceStore {
        let marketplace = libraryRoot.appendingPathComponent("marketplace", isDirectory: true)
        let sources = marketplacePlugins.map { plugin in
            MarketplaceSource(marketplace.absoluteString, path: "plugins/\(plugin)", alias: plugin)
        }
        return MarketplaceStore(
            sources: sources,
            layout: MarketplaceLayout(documentName: skillDocumentName),
            cacheDirectory: cacheDirectory)
    }
}
