import Foundation
import Marketplace
import MarketplaceFixtures

/// A marketplace provider over the fixture marketplace at
/// `Examples/agent-library/marketplace` (plan.md §6.1, §13).
///
/// `make()` commits each file of the fixture marketplace to a new
/// `GitFixtureRepository`, and installs the commit with a `MarketplaceStore`
/// over a new cache folder. The snapshot of the store has the §6.1 shape:
/// `agents/<id>.md` for each agent of all plugins, each skill folder at the
/// layer root, and `_partials/`. The provider gives the layers of that store.
///
/// The provider makes no network call. The test calls `delete()` in a
/// `defer`.
struct FixtureMarketplaceProvider: MarketplaceLayerProviding {
    /// The display id of the fixture marketplace: the `name` field of its
    /// catalog.
    static let marketplaceID = "agent-library"

    /// The `version` field of the metadata of the fixture catalog.
    static let catalogVersion = "1.0.0"

    /// The agent ids of the snapshot, sorted.
    static let agentIDs = ["doc-writer", "security-reviewer"]

    /// The commit that the store installed.
    let sha: String

    /// The cache folder of the store.
    private let cache: TemporaryLayer

    /// The store that gives the layers.
    private let store: MarketplaceStore

    /// Commits the fixture marketplace, and installs it with a new store.
    ///
    /// - Parameter select: The selection of the source. The default is
    ///   `.all`.
    /// - Returns: The provider, with the snapshot installed.
    /// - Throws: The error of a file read, of the repository, or of the
    ///   cache folder.
    static func make(select: SkillSelection = .all) async throws -> FixtureMarketplaceProvider {
        let unstarted = try makeUnstarted(select: select)
        await unstarted.start()
        return unstarted.provider
    }

    /// Commits the fixture marketplace, and makes a new store over it that
    /// has not started. The store gives no layer until `start()`.
    ///
    /// - Parameter select: The selection of the source. The default is
    ///   `.all`.
    /// - Returns: The provider with no snapshot installed, and the fixtures
    ///   that the store reads when it starts.
    /// - Throws: The error of a file read, of the repository, or of the
    ///   cache folder.
    static func makeUnstarted(select: SkillSelection = .all) throws -> Unstarted {
        let repository = try GitFixtureRepository()
        let sha = try repository.commit(files: fixtureTree())
        let cache = try TemporaryLayer.makeEmpty()
        let fixture = try MarketplaceStoreFixture(
            sources: [MarketplaceSource(repository.url, select: select)], cacheDirectory: cache.root)
        let provider = FixtureMarketplaceProvider(sha: sha, cache: cache, store: fixture.store)
        return Unstarted(provider: provider, repository: repository, fixture: fixture)
    }

    /// A provider whose store has not started, with the fixtures that the
    /// store reads when it starts.
    ///
    /// The repository and the store fixture remove their folders when they
    /// are released. This value keeps them until `start()` returns. A test
    /// that makes a new commit and updates the store keeps this value until
    /// its end.
    struct Unstarted {
        /// The provider. It gives no layer until `start()`.
        let provider: FixtureMarketplaceProvider

        /// The repository that holds the commit of the fixture marketplace.
        let repository: GitFixtureRepository

        /// The store fixture: its local folder is the source of the store.
        let fixture: MarketplaceStoreFixture

        /// Starts the store: it installs the snapshot of the fixture
        /// marketplace, as `market.start()` does in a host.
        func start() async {
            await provider.store.start()
            withExtendedLifetime((repository, fixture)) {}
        }
    }

    /// Gives the layers of the store, lowest precedence first.
    ///
    /// - Returns: The one layer of the fixture marketplace.
    func marketplaceLayers() -> [MarketplaceLayer] {
        store.marketplaceLayers()
    }

    /// The updates of the store.
    var layerUpdates: AsyncStream<Void> {
        store.layerUpdates
    }

    /// Removes the cache folder and the snapshot in it.
    ///
    /// - Throws: The error of the file system when it cannot remove the
    ///   folder.
    func delete() throws {
        try cache.delete()
    }

    /// Reads each file of the fixture marketplace, the hidden
    /// `.claude-plugin/` folder too.
    ///
    /// - Returns: The tree of one commit, one entry for each path relative to
    ///   the marketplace folder.
    /// - Throws: The error of the file system when it cannot read a file.
    static func fixtureTree() throws -> [String: GitFixtureRepository.Entry] {
        let root = FixtureLibrary.marketplaceDirectory
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path).filter { path in
            isFile(root.appendingPathComponent(path))
        }
        return try Dictionary(
            uniqueKeysWithValues: files.map { path in
                (path, .file(try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)))
            })
    }

    /// Tells if `url` names a file and not a folder.
    ///
    /// - Parameter url: The URL to test.
    /// - Returns: `true` when a file is at `url`.
    private static func isFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}
