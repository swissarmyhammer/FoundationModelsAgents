import Foundation
@testable import FoundationModelsAgents
import Testing

/// Pins ``AgentRegistry/rootAgent(in:id:)``: the read of the root `AGENT.md`
/// of one folder, with no registry and no catalog.
///
/// A folder with an `AGENT.md` at its root is an agent (D71). The read uses
/// the coordinated read and the parser of the catalog build, as a layer with
/// the source `project` at the folder. It reads only `<folder>/AGENT.md`.
@Suite("Root agent")
struct RootAgentTests {
    /// The id that a host gives for the folder `Agents/reviewer/`.
    private static let reviewerID = "reviewer"

    /// An id that ``AgentDefinitionRules/isValidID(_:)`` refuses.
    private static let invalidID = "Not An ID"

    /// The body of the root `AGENT.md`.
    private static let rootBody = "You are the agent of this folder."

    /// The text of a valid root `AGENT.md`, with ``rootBody``.
    private static let rootText = AgentFolderFixture.agentText(
        name: AgentFolderFixture.displayName, body: rootBody)

    /// Makes a folder that holds a valid root `AGENT.md`.
    ///
    /// - Returns: The folder. The test deletes it.
    private static func makeAgentFolder() throws -> TemporaryLayer {
        try TemporaryLayer.make(holding: [AgentDocumentPath.documentName: rootText])
    }

    @Test("a folder with an AGENT.md gives its definition")
    func aFolderWithAnAgentDocumentGivesItsDefinition() throws {
        let folder = try Self.makeAgentFolder()
        defer { try? folder.delete() }

        let load = AgentRegistry.rootAgent(in: folder.root)

        #expect(load.definition?.body.contains(Self.rootBody) == true)
    }

    @Test("a folder with an AGENT.md gives no diagnostic")
    func aFolderWithAnAgentDocumentGivesNoDiagnostic() throws {
        let folder = try Self.makeAgentFolder()
        defer { try? folder.delete() }

        let load = AgentRegistry.rootAgent(in: folder.root)

        #expect(load.diagnostics.isEmpty)
    }

    @Test("the definition comes from a layer with the source project")
    func theDefinitionHasTheProjectSource() throws {
        let folder = try Self.makeAgentFolder()
        defer { try? folder.delete() }

        let definition = try #require(AgentRegistry.rootAgent(in: folder.root).definition)

        #expect(definition.layer.source == .project)
    }

    @Test("the definition has the URL of the root AGENT.md of the folder")
    func theDefinitionHasTheURLOfTheRootDocument() throws {
        let folder = try Self.makeAgentFolder()
        defer { try? folder.delete() }

        let definition = try #require(AgentRegistry.rootAgent(in: folder.root).definition)

        #expect(definition.url == folder.root.appendingPathComponent(AgentDocumentPath.documentName))
    }

    @Test("a folder with no AGENT.md gives no definition and no diagnostic")
    func aFolderWithNoAgentDocumentGivesNothing() throws {
        let folder = try TemporaryLayer.makeEmpty()
        defer { try? folder.delete() }

        let load = AgentRegistry.rootAgent(in: folder.root)

        #expect(load.definition == nil && load.diagnostics.isEmpty)
    }

    @Test("a file with no frontmatter gives no definition and the noFrontmatter diagnostic")
    func aFileWithNoFrontmatterGivesItsDiagnostic() throws {
        let folder = try TemporaryLayer.make(holding: [AgentDocumentPath.documentName: Self.rootBody])
        defer { try? folder.delete() }

        let load = AgentRegistry.rootAgent(in: folder.root)

        #expect(load.definition == nil)
        #expect(load.diagnostics.map(\.code) == [.noFrontmatter])
    }

    @Test("a placeholder of AGENT.md gives no definition and the not-local diagnostic of the catalog build")
    func aPlaceholderGivesTheNotLocalDiagnostic() throws {
        let folder = try TemporaryLayer.make(holding: [AgentFolderFixture.documentPlaceholderName: ""])
        defer { try? folder.delete() }

        let load = AgentRegistry.rootAgent(in: folder.root)

        #expect(load.definition == nil)
        #expect(load.diagnostics.map(\.message) == [AgentCatalogBuilder.notLocalMessage])
    }

    @Test("a call with no id gives the id default")
    func aCallWithNoIDGivesTheDefaultID() throws {
        let folder = try Self.makeAgentFolder()
        defer { try? folder.delete() }

        let load = AgentRegistry.rootAgent(in: folder.root)

        #expect(load.definition?.id == AgentCatalog.defaultAgentID)
    }

    @Test("a call with an id gives the definition that id")
    func aCallWithAnIDGivesThatID() throws {
        let folder = try Self.makeAgentFolder()
        defer { try? folder.delete() }

        let load = AgentRegistry.rootAgent(in: folder.root, id: Self.reviewerID)

        #expect(load.definition?.id == Self.reviewerID)
    }

    @Test("a call with an invalid id gives no definition and the invalidID diagnostic")
    func aCallWithAnInvalidIDGivesItsDiagnostic() throws {
        let folder = try Self.makeAgentFolder()
        defer { try? folder.delete() }

        let load = AgentRegistry.rootAgent(in: folder.root, id: Self.invalidID)

        #expect(load.definition == nil)
        #expect(load.diagnostics.map(\.code) == [.invalidID])
    }

    @Test("neither <folder>/<id>/AGENT.md nor <folder>/agents/<id>/AGENT.md loads")
    func onlyTheRootDocumentLoads() throws {
        let folder = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: Self.reviewerID): AgentFolderFixture.agentText(
                name: Self.reviewerID),
            AgentDocumentPath.of(AgentFolderFixture.helperID): AgentFolderFixture.agentText(
                name: AgentFolderFixture.helperID)
        ])
        defer { try? folder.delete() }

        let byID = AgentRegistry.rootAgent(in: folder.root, id: Self.reviewerID)
        let byHelperID = AgentRegistry.rootAgent(in: folder.root, id: AgentFolderFixture.helperID)
        let byDefault = AgentRegistry.rootAgent(in: folder.root)

        #expect([byID, byHelperID, byDefault].allSatisfy { $0.definition == nil && $0.diagnostics.isEmpty })
    }
}
