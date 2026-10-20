import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the watch of the agent folder form of a local layer: with
/// `watch: true`, the `DotfolderWatcher` watches each local layer root, thus
/// it sees a change of `<root>/<id>/AGENT.md`.
///
/// Each row uses the real watcher, thus it waits on `onReload` for the
/// catalog that it expects.
@Suite("Agent folder watch")
struct AgentFolderWatchTests {
    @Test("the root of a root settings folder is watched: a new agent gives a new catalog")
    func newAgentInAWatchedAgentFolderGivesANewCatalog() async throws {
        let id = AgentFolderFixture.helperID
        let folder = try TemporaryLayer.makeEmpty()
        defer { try? folder.delete() }
        let registry = AgentRegistry(layers: [folder.userLayer], watch: true)
        try await registry.load()
        let reloads = registry.onReload

        try folder.write(AgentFolderFixture.agentText(name: id), at: AgentFolderFixture.documentPath(of: id))

        let published = try #require(await reloads.first { $0.definition(named: id) != nil })
        #expect(published.definitions.map(\.id) == [id])
    }

    @Test("a placeholder that becomes the full AGENT.md gives a catalog with the agent")
    func placeholderThatBecomesTheDocumentGivesTheAgent() async throws {
        let id = AgentFolderFixture.helperID
        let placeholderPath = "\(id)/\(AgentFolderFixture.documentPlaceholderName)"
        let folder = try TemporaryLayer.make(holding: [placeholderPath: ""])
        defer { try? folder.delete() }
        let registry = AgentRegistry(layers: [folder.userLayer], watch: true)
        let first = try await registry.loadedCatalog()
        let reloads = registry.onReload

        try folder.write(AgentFolderFixture.agentText(name: id), at: placeholderPath)
        try FileManager.default.moveItem(
            at: folder.root.appendingPathComponent(placeholderPath),
            to: folder.root.appendingPathComponent(AgentFolderFixture.documentPath(of: id)))

        let published = try #require(await reloads.first { $0.definition(named: id) != nil })
        #expect(first.definition(named: id) == nil)
        #expect(published.diagnostics.isEmpty)
    }
}
