import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the render of the body of an agent from an agent-folder source.
///
/// The include walk of `<url>/<id>/AGENT.md` is `<id>/_partials/`, then
/// `_partials/` of the source root. The default agent `<url>/AGENT.md` uses
/// `_partials/` of the source root. The walk never reads a partial of a
/// different source.
@Suite("Agent folder render")
struct AgentFolderRenderTests {
    /// The prompt of each render.
    private static let prompt = "Review the change."

    /// The text of the partial in the agent folder.
    private static let folderRules = "## Folder House Rules"

    /// The text of the partial at the source root.
    private static let rootRules = "## Root House Rules"

    /// The text of the partial of a dotfolder layer.
    private static let projectRules = "## Project House Rules"

    @Test("a copy in <id>/_partials/ wins over the copy at the source root")
    func agentFolderPartialWins() async throws {
        let id = AgentFolderFixture.helperID
        let folder = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: id): AgentFolderFixture.includingAgentText(name: id),
            AgentFolderFixture.partialPath(in: id): Self.folderRules,
            AgentFolderFixture.partialPath(in: nil): Self.rootRules
        ])
        defer { try? folder.delete() }

        let rendered = try await Self.render(id, in: AgentRegistry(layers: [], agentFolders: [folder.root]))

        #expect(rendered.contains(Self.folderRules))
        #expect(!rendered.contains(Self.rootRules))
    }

    @Test("an include of the default agent resolves to _partials/ of the source root")
    func defaultAgentIncludesTheRootPartial() async throws {
        let folder = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.includingAgentText(name: AgentFolderFixture.displayName),
            AgentFolderFixture.partialPath(in: nil): Self.rootRules
        ])
        defer { try? folder.delete() }

        let registry = AgentRegistry(layers: [], agentFolders: [folder.root])
        let rendered = try await Self.render(AgentFolderFixture.defaultAgentID, in: registry)

        #expect(rendered.contains(Self.rootRules))
    }

    @Test("an agent-folder agent does not read a partial of a dotfolder layer")
    func agentFolderAgentDoesNotReadADotfolderPartial() async throws {
        let id = AgentFolderFixture.helperID
        let project = try TemporaryLayer.make(holding: [AgentFolderFixture.partialPath(in: nil): Self.projectRules])
        defer { try? project.delete() }
        let folder = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: id): AgentFolderFixture.includingAgentText(name: id)
        ])
        defer { try? folder.delete() }
        let registry = AgentRegistry(layers: [project.layer], agentFolders: [folder.root])

        await #expect(throws: AgentRunFailure.self) {
            _ = try await Self.render(id, in: registry)
        }
    }

    @Test("a dotfolder agent does not read a partial of an agent-folder source")
    func dotfolderAgentDoesNotReadAnAgentFolderPartial() async throws {
        let id = AgentFolderFixture.helperID
        let project = try TemporaryLayer.make(holding: [
            AgentDocumentPath.of(id): AgentFolderFixture.includingAgentText(name: id)
        ])
        defer { try? project.delete() }
        let folder = try TemporaryLayer.make(holding: [AgentFolderFixture.partialPath(in: nil): Self.rootRules])
        defer { try? folder.delete() }
        let registry = AgentRegistry(layers: [project.layer], agentFolders: [folder.root])

        await #expect(throws: AgentRunFailure.self) {
            _ = try await Self.render(id, in: registry)
        }
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
