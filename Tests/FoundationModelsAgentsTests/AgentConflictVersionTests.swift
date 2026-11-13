import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Synchronization
import Testing

/// Pins the conflict versions of the `agents` endpoint (TestudoApp D154):
/// `Agent.conflicts` gives the unresolved conflict versions of the file of
/// each agent, and a new version or a resolve from the source gives one
/// `AgentChange` with the id of the agent in `changed`.
///
/// Each test uses ``FakeConflictSource``. A test that waits for a change
/// reads the subscription, and the read also ends when the stream ends
/// (test rule T1).
@Suite("Agent conflict versions")
struct AgentConflictVersionTests {
    /// The agent with the conflict.
    private static let conflictedID = "alpha"

    /// The agent with no conflict.
    private static let plainID = "bravo"

    /// The conflict version of the tests.
    private static let version = AgentConflictVersion(
        id: "version-1", deviceName: "Work iPad", modificationDate: Date(timeIntervalSince1970: 1_800_000_000))

    /// The query of the conflicts of each agent.
    private static let conflictsQuery = "{ agents { id conflicts { id deviceName modifiedAt } } }"

    /// Makes a layer with the two agents and a registry over it with the
    /// fake source, and loads the registry.
    ///
    /// - Parameters:
    ///   - source: The fake source.
    ///   - watch: Whether the registry follows the changes.
    /// - Returns: The layer and the registry. The test deletes the layer.
    private static func load(
        _ source: FakeConflictSource, watch: Bool
    ) async throws -> (layer: TemporaryLayer, registry: AgentRegistry) {
        let layer = try AgentsGraphTests.makeLayer(ids: [conflictedID, plainID])
        let registry = AgentRegistry(layers: [layer.layer], watch: watch, conflictVersions: source)
        try await registry.load()
        return (layer, registry)
    }

    /// Gives the conflicts of each agent from the endpoint.
    ///
    /// - Parameter registry: The registry.
    /// - Returns: The conflict objects of each agent, by agent id.
    private static func conflicts(in registry: AgentRegistry) async throws -> [String: [[String: Any]]] {
        let text = try await registry.agentsGraph().execute(
            query: conflictsQuery, variables: [:], operationName: nil, viewer: nil)
        let agents = try GraphQLReply(text).objects("agents")
        return try Dictionary(uniqueKeysWithValues: agents.map { agent in
            (try #require(agent["id"] as? String), try #require(agent["conflicts"] as? [[String: Any]]))
        })
    }

    /// Gives the wire text of the `DateTime` of a date.
    ///
    /// - Parameter date: The date.
    /// - Returns: The RFC 3339 text.
    private static func wireText(of date: Date) throws -> String {
        try #require(String(data: JSONEncoder().encode([DateTime(date)]), encoding: .utf8))
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]\""))
    }

    @Test("Agent.conflicts gives the conflict versions of the source, and an empty list for an agent with none")
    func theEndpointListsTheConflicts() async throws {
        let source = FakeConflictSource()
        source.set([Self.version], for: Self.conflictedID)
        let (layer, registry) = try await Self.load(source, watch: false)
        defer { try? layer.delete() }

        let conflicts = try await Self.conflicts(in: registry)

        let conflict = try #require(conflicts[Self.conflictedID]?.first)
        #expect(conflicts[Self.conflictedID]?.count == 1)
        #expect(conflict["id"] as? String == Self.version.id)
        #expect(conflict["deviceName"] as? String == Self.version.deviceName)
        #expect(conflict["modifiedAt"] as? String == (try Self.wireText(of: try #require(Self.version.modificationDate))))
        #expect(conflicts[Self.plainID]?.isEmpty == true)
        #expect(registry.catalog().conflicts(of: Self.conflictedID) == [Self.version])
        #expect(registry.catalog().conflicts(of: Self.plainID).isEmpty)
    }

    @Test("a version with no device name and no date gives null for each")
    func unknownFieldsAreNull() async throws {
        let source = FakeConflictSource()
        source.set([AgentConflictVersion(id: "bare", deviceName: nil, modificationDate: nil)], for: Self.conflictedID)
        let (layer, registry) = try await Self.load(source, watch: false)
        defer { try? layer.delete() }

        let conflict = try #require(try await Self.conflicts(in: registry)[Self.conflictedID]?.first)

        #expect(conflict["deviceName"] is NSNull)
        #expect(conflict["modifiedAt"] is NSNull)
    }

    @Test("a new conflict version from the source gives a change event, then a resolve gives one more")
    func aConflictAndAResolveEachGiveAnEvent() async throws {
        let source = FakeConflictSource()
        let (layer, registry) = try await Self.load(source, watch: true)
        defer { try? layer.delete() }
        let graph = try registry.agentsGraph()
        let start = try await ChangeEvent.cursor(of: graph)

        source.set([Self.version], for: Self.conflictedID)
        let gained = try await ChangeEvent.first(after: start, of: graph)

        #expect(gained.ids == ChangedIDs(changed: [Self.conflictedID]))
        #expect(try await Self.conflicts(in: registry)[Self.conflictedID]?.count == 1)

        source.set([], for: Self.conflictedID)
        let resolved = try await ChangeEvent.first(after: gained.cursor, of: graph)

        #expect(resolved.ids == ChangedIDs(changed: [Self.conflictedID]))
        #expect(try await Self.conflicts(in: registry)[Self.conflictedID]?.isEmpty == true)
    }

    @Test("the registry follows the changes of the source under its layer roots")
    func theRegistryFollowsTheLayerRoots() async throws {
        let source = FakeConflictSource()
        let (layer, registry) = try await Self.load(source, watch: true)
        defer { try? layer.delete() }

        #expect(source.followedRoots == [[layer.layer.root]])
        await registry.stopWatching()
    }

    @Test("stopWatching() stops the follow of the source")
    func stopWatchingStopsTheSource() async throws {
        let source = FakeConflictSource()
        let terminations = source.terminations
        let (layer, registry) = try await Self.load(source, watch: true)
        defer { try? layer.delete() }

        await registry.stopWatching()

        #expect(await terminations.first { _ in true } != nil)
    }

    @Test("a registry with watch: false does not follow the source")
    func noWatchDoesNotFollowTheSource() async throws {
        let source = FakeConflictSource()
        let (layer, _) = try await Self.load(source, watch: false)
        defer { try? layer.delete() }

        #expect(source.followedRoots.isEmpty)
    }

    @Test("the presenter of a root calls its handler for a gained, a lost and a resolved version")
    func thePresenterForwardsEachVersionEvent() throws {
        let layer = try AgentsGraphTests.makeLayer(ids: [Self.conflictedID])
        defer { try? layer.delete() }
        let url = layer.root.appendingPathComponent(AgentFolderFixture.documentPath(of: Self.conflictedID))
        let version = try #require(NSFileVersion.currentVersionOfItem(at: url))
        let calls = CallRecord<Int>()
        let presenter = ConflictVersionPresenter(root: layer.root) { calls.add(1) }

        presenter.presentedSubitem(at: url, didGain: version)
        presenter.presentedSubitem(at: url, didLose: version)
        presenter.presentedSubitem(at: url, didResolveConflict: version)

        #expect(calls.all.count == 3)
        #expect(presenter.presentedItemURL == layer.root)
    }

    @Test("FileVersionConflictSource gives no version for a file that is not in a synced folder")
    func theFileVersionSourceGivesNoVersionForAPlainFile() throws {
        let layer = try AgentsGraphTests.makeLayer(ids: [Self.conflictedID])
        defer { try? layer.delete() }
        let url = layer.root.appendingPathComponent(AgentFolderFixture.documentPath(of: Self.conflictedID))

        #expect(FileVersionConflictSource().conflictVersions(of: url).isEmpty)
    }
}

/// A conflict version source that a test controls.
///
/// ``set(_:for:)`` changes the versions of the file of one agent, by the
/// name of its folder, and sends a value to each stream of
/// ``changes(under:)``. The termination of a stream gives a value on
/// ``terminations``.
private final class FakeConflictSource: AgentConflictVersionSource {
    /// The versions of the file of each agent, by the name of its folder.
    private let versions = Mutex<[String: [AgentConflictVersion]]>([:])

    /// The continuation of each open stream of ``changes(under:)``, by a key
    /// of its own.
    private let followers = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])

    /// The roots of each call of ``changes(under:)``, in order.
    private let roots = Mutex<[[URL]]>([])

    /// The continuation of ``terminations``.
    private let terminated: AsyncStream<Void>.Continuation

    /// One value for each stream of ``changes(under:)`` that terminated.
    let terminations: AsyncStream<Void>

    /// Makes a source with no version.
    init() {
        (terminations, terminated) = AsyncStream<Void>.makeStream()
    }

    /// The roots of each call of ``changes(under:)``, in order.
    var followedRoots: [[URL]] {
        roots.withLock { $0 }
    }

    /// Sets the versions of the file of one agent, and sends a value to each
    /// open stream.
    ///
    /// - Parameters:
    ///   - list: The versions.
    ///   - id: The name of the folder of the agent.
    func set(_ list: [AgentConflictVersion], for id: String) {
        versions.withLock { $0[id] = list }
        followers.withLock { followers in
            for follower in followers.values {
                follower.yield()
            }
        }
    }

    /// Gives the versions of the file of one agent, by the name of the
    /// folder of the file.
    ///
    /// - Parameter url: The URL of the agent file.
    /// - Returns: The versions.
    func conflictVersions(of url: URL) -> [AgentConflictVersion] {
        let id = url.deletingLastPathComponent().lastPathComponent
        return versions.withLock { $0[id] ?? [] }
    }

    /// Gives a stream that gets a value for each ``set(_:for:)`` call.
    ///
    /// - Parameter roots: The roots to follow.
    /// - Returns: The stream.
    func changes(under roots: [URL]) -> AsyncStream<Void> {
        self.roots.withLock { $0.append(roots) }
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let key = UUID()
        followers.withLock { $0[key] = continuation }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            _ = followers.withLock { $0.removeValue(forKey: key) }
            terminated.yield()
        }
        return stream
    }
}
