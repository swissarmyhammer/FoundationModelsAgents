import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins `AgentRegistry.stopWatching()`: after the call, the watcher is
/// stopped, a change of a layer gives no new catalog, and `catalog()` keeps
/// the last catalog.
///
/// A test cannot wait for an event that does not occur. Thus each row that
/// proves "no new catalog" also watches the same folder with a control
/// registry that is not stopped. The row waits on the control registry for
/// the change, and then checks that the stopped registry has no watcher and
/// did not rebuild its catalog.
@Suite("AgentRegistry stopWatching")
struct AgentRegistryStopWatchingTests {
    @Test("after stopWatching(), a new AGENT.md gives no new catalog")
    func newAgentAfterStopGivesNoNewCatalog() async throws {
        let id = AgentFolderFixture.helperID
        let folder = try TemporaryLayer.makeEmpty()
        defer { try? folder.delete() }
        let stopped = AgentRegistry(layers: [folder.userLayer], watch: true)
        let control = AgentRegistry(layers: [folder.userLayer], watch: true)
        try await stopped.load()
        try await control.load()
        #expect(stopped.reloads.isWatching)
        let controlReloads = control.onReload

        await stopped.stopWatching()
        try writeHelperAgent(in: folder)

        let seen = try #require(await controlReloads.first { $0.definition(named: id) != nil })
        #expect(seen.definitions.map(\.id) == [id])
        #expect(!stopped.reloads.isWatching)
        #expect(stopped.catalog().definitions.isEmpty)
    }

    @Test("a second stopWatching() call does nothing")
    func secondStopDoesNothing() async throws {
        let folder = try TemporaryLayer.makeEmpty()
        defer { try? folder.delete() }
        let registry = AgentRegistry(layers: [folder.userLayer], watch: true)
        try await registry.load()

        await registry.stopWatching()
        await registry.stopWatching()

        #expect(!registry.reloads.isWatching)
        #expect(registry.isLoaded)
    }

    @Test("a reload after stopWatching() rebuilds the catalog and starts no watcher")
    func reloadAfterStopStartsNoWatcher() async throws {
        let id = AgentFolderFixture.helperID
        let folder = try TemporaryLayer.makeEmpty()
        defer { try? folder.delete() }
        let registry = AgentRegistry(layers: [folder.userLayer], watch: true)
        try await registry.load()
        await registry.stopWatching()

        try writeHelperAgent(in: folder)
        try await registry.reload()

        #expect(registry.catalog().definition(named: id) != nil)
        #expect(!registry.reloads.isWatching)
    }

    @Test("stopWatching() before load() stops the registry before it watches")
    func stopBeforeLoadStartsNoWatcher() async throws {
        let folder = try TemporaryLayer.makeEmpty()
        defer { try? folder.delete() }
        let registry = AgentRegistry(layers: [folder.userLayer], watch: true)

        await registry.stopWatching()
        try await registry.load()

        #expect(registry.isLoaded)
        #expect(!registry.reloads.isWatching)
    }

    @Test("stopWatching() on a registry with watch: false does nothing")
    func stopWithNoWatchDoesNothing() async throws {
        let id = AgentFolderFixture.helperID
        let folder = try TemporaryLayer.makeEmpty()
        defer { try? folder.delete() }
        let registry = AgentRegistry(layers: [folder.userLayer], watch: false)
        try await registry.load()
        #expect(!registry.reloads.isWatching)

        await registry.stopWatching()
        try writeHelperAgent(in: folder)
        try await registry.reload()

        #expect(registry.catalog().definition(named: id) != nil)
    }
}

/// Writes the `AGENT.md` of the agent `AgentFolderFixture.helperID` in the
/// agent folder form of `folder`.
///
/// - Parameter folder: The layer to write in.
private func writeHelperAgent(in folder: TemporaryLayer) throws {
    let id = AgentFolderFixture.helperID
    try folder.write(AgentFolderFixture.agentText(name: id), at: AgentFolderFixture.documentPath(of: id))
}
