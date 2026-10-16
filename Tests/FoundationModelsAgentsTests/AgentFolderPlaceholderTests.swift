import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the files of an agent-folder source that a sync engine did not make
/// local yet, and the files that are not an agent document.
///
/// A placeholder name or a document that the build cannot read gives one
/// diagnostic, "the agent document is not local yet", and never fails the
/// catalog. Only the exact name `AGENT.md` is an agent document.
@Suite("Agent folder placeholders")
struct AgentFolderPlaceholderTests {
    /// The text of the diagnostic for a document that is not local yet.
    private static let notLocalText = "the agent document is not local yet"

    /// The placeholder of an agent document.
    private static let documentPlaceholderName = AgentFolderFixture.documentPlaceholderName

    /// The placeholder of the agent folder of `AgentFolderFixture.helperID`.
    private static let folderPlaceholderName = ".\(AgentFolderFixture.helperID)\(AgentFolderFixture.placeholderSuffix)"

    /// The name of a conflict copy of an agent document.
    private static let conflictCopyName = "AGENT 2.md"

    /// The body of the conflict copy, which the agent must not get.
    private static let conflictBody = "The body of the conflict copy."

    /// Bytes that are not UTF-8 text: a lone continuation byte.
    private static let unreadableBytes = Data([0xFF, 0xFE, 0x80])

    /// The id of a second agent that loads next to a placeholder.
    private static let goodID = "good-agent"

    @Test("a placeholder of <id>/AGENT.md gives one not-local diagnostic, and the agent next to it loads")
    func documentPlaceholderGivesOneDiagnostic() async throws {
        let id = AgentFolderFixture.helperID
        let placeholderPath = "\(id)/\(Self.documentPlaceholderName)"
        let folder = try TemporaryLayer.make(holding: [
            placeholderPath: "",
            AgentFolderFixture.documentPath(of: Self.goodID): AgentFolderFixture.agentText(name: Self.goodID)
        ])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [], agentFolders: [folder.root]).loadedCatalog()
        let diagnostic = try #require(catalog.diagnostics.first)

        #expect(catalog.definitions.map(\.id) == [Self.goodID])
        #expect(catalog.diagnostics.count == 1)
        #expect(diagnostic.agent == id)
        #expect(diagnostic.severity == .skip)
        #expect(diagnostic.message.contains(Self.notLocalText))
        #expect(diagnostic.provenance.url == folder.root.appendingPathComponent(placeholderPath))
    }

    @Test("a placeholder of the root AGENT.md gives one not-local diagnostic for the default agent")
    func rootPlaceholderGivesOneDiagnostic() async throws {
        let folder = try TemporaryLayer.make(holding: [Self.documentPlaceholderName: ""])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [], agentFolders: [folder.root]).loadedCatalog()
        let diagnostic = try #require(catalog.diagnostics.first)

        #expect(catalog.defaultAgent == nil)
        #expect(catalog.diagnostics.count == 1)
        #expect(diagnostic.agent == AgentFolderFixture.defaultAgentID)
        #expect(diagnostic.message.contains(Self.notLocalText))
    }

    @Test("a placeholder of a whole agent folder gives one not-local diagnostic for that agent")
    func folderPlaceholderGivesOneDiagnostic() async throws {
        let folder = try TemporaryLayer.make(holding: [Self.folderPlaceholderName: ""])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [], agentFolders: [folder.root]).loadedCatalog()
        let diagnostic = try #require(catalog.diagnostics.first)

        #expect(catalog.definitions.isEmpty)
        #expect(catalog.diagnostics.count == 1)
        #expect(diagnostic.agent == AgentFolderFixture.helperID)
        #expect(diagnostic.message.contains(Self.notLocalText))
        #expect(diagnostic.provenance.url == folder.root.appendingPathComponent(Self.folderPlaceholderName))
    }

    @Test("an AGENT.md that the build cannot read gives one not-local diagnostic")
    func unreadableDocumentGivesOneDiagnostic() async throws {
        let id = AgentFolderFixture.helperID
        let folder = try TemporaryLayer.makeEmpty()
        defer { try? folder.delete() }
        let documentURL = folder.root.appendingPathComponent(AgentFolderFixture.documentPath(of: id))
        try FileManager.default.createDirectory(
            at: documentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.unreadableBytes.write(to: documentURL)

        let catalog = try await AgentRegistry(layers: [], agentFolders: [folder.root]).loadedCatalog()
        let diagnostic = try #require(catalog.diagnostics.first)

        #expect(catalog.definitions.isEmpty)
        #expect(catalog.diagnostics.count == 1)
        #expect(diagnostic.agent == id)
        #expect(diagnostic.message.contains(Self.notLocalText))
        #expect(diagnostic.provenance.url == documentURL)
    }

    @Test("a conflict copy is a resource: it gives no diagnostic and does not change the agent")
    func conflictCopyIsAResource() async throws {
        let id = AgentFolderFixture.helperID
        let text = AgentFolderFixture.agentText(name: id)
        let folder = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: id): text,
            "\(id)/\(Self.conflictCopyName)": AgentFolderFixture.agentText(name: id, body: Self.conflictBody),
            Self.conflictCopyName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName)
        ])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [], agentFolders: [folder.root]).loadedCatalog()
        let definition = try #require(catalog.definition(named: id))

        #expect(catalog.definitions.map(\.id) == [id])
        #expect(catalog.diagnostics.isEmpty)
        #expect(catalog.defaultAgent == nil)
        #expect(!definition.body.contains(Self.conflictBody))
    }
}
