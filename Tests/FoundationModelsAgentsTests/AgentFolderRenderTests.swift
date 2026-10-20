import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the render of the body of an agent of the agent folder form of a
/// local layer.
///
/// The include walk of `<root>/<id>/AGENT.md` is `<id>/_partials/`, then
/// `_partials/` of the layer root. The default agent `<root>/AGENT.md` uses
/// `_partials/` of the layer root. The walk never reads a partial of a
/// different layer. A document of the dotfolder form `agents/<id>/AGENT.md`
/// sees the partials of each local layer.
@Suite("Agent folder render")
struct AgentFolderRenderTests {
    /// The prompt of each render.
    private static let prompt = "Review the change."

    /// The text of the partial in the agent folder.
    private static let folderRules = "## Folder House Rules"

    /// The text of the partial at the layer root.
    private static let rootRules = "## Root House Rules"

    /// The text of the partial of the project layer.
    private static let projectRules = "## Project House Rules"

    @Test("a copy in <id>/_partials/ wins over the copy at the layer root")
    func agentFolderPartialWins() async throws {
        let id = AgentFolderFixture.helperID
        let folder = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: id): AgentFolderFixture.includingAgentText(name: id),
            AgentFolderFixture.partialPath(in: id): Self.folderRules,
            AgentFolderFixture.partialPath(in: nil): Self.rootRules
        ])
        defer { try? folder.delete() }

        let rendered = try await Self.render(id, in: AgentRegistry(layers: [folder.userLayer]))

        #expect(rendered.contains(Self.folderRules))
        #expect(!rendered.contains(Self.rootRules))
    }

    @Test("an include of the default agent resolves to _partials/ of the layer root")
    func defaultAgentIncludesTheRootPartial() async throws {
        let folder = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.includingAgentText(name: AgentFolderFixture.displayName),
            AgentFolderFixture.partialPath(in: nil): Self.rootRules
        ])
        defer { try? folder.delete() }

        let registry = AgentRegistry(layers: [folder.userLayer])
        let rendered = try await Self.render(AgentFolderFixture.defaultAgentID, in: registry)

        #expect(rendered.contains(Self.rootRules))
    }

    @Test("an agent of the agent folder form does not read a partial of a different layer")
    func agentFolderAgentDoesNotReadADifferentLayerPartial() async throws {
        let id = AgentFolderFixture.helperID
        let project = try TemporaryLayer.make(holding: [AgentFolderFixture.partialPath(in: nil): Self.projectRules])
        defer { try? project.delete() }
        let folder = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: id): AgentFolderFixture.includingAgentText(name: id)
        ])
        defer { try? folder.delete() }
        let registry = AgentRegistry(layers: [folder.userLayer, project.layer])

        await #expect(throws: AgentRunFailure.self) {
            _ = try await Self.render(id, in: registry)
        }
    }

    @Test("a dotfolder agent of the project layer reads _partials/ of the root settings folder")
    func dotfolderAgentReadsALowerLayerPartial() async throws {
        let id = AgentFolderFixture.helperID
        let project = try TemporaryLayer.make(holding: [
            AgentDocumentPath.of(id): AgentFolderFixture.includingAgentText(name: id)
        ])
        defer { try? project.delete() }
        let folder = try TemporaryLayer.make(holding: [AgentFolderFixture.partialPath(in: nil): Self.rootRules])
        defer { try? folder.delete() }
        let registry = AgentRegistry(layers: [folder.userLayer, project.layer])

        let rendered = try await Self.render(id, in: registry)

        #expect(rendered.contains(Self.rootRules))
    }

    /// Loads `registry`, and renders the body of the agent `id`.
    ///
    /// - Parameters:
    ///   - id: The agent id.
    ///   - registry: The registry to load.
    /// - Returns: The rendered body.
    /// - Throws: The error of `load()`, the error of `#require` when the
    ///   catalog has no such agent, or the render failure.
    private static func render(_ id: String, in registry: AgentRegistry) async throws -> String {
        let definition = try #require(try await registry.loadedCatalog().definition(named: id))
        return try AgentBodyRenderer(registry: registry).render(definition, prompt: prompt)
    }
}
