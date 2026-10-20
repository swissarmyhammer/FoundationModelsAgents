import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the files of the agent folder form of a local layer that a sync
/// engine did not make local yet, and the files that are not an agent
/// document.
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

    /// The id that the usual hidden file `.env.local` holds before its dot.
    private static let envID = "env"

    /// A usual hidden file at the layer root. It is not a placeholder.
    private static let envFileName = ".\(envID).local"

    /// The placeholder of a root resource `helper`, not of an agent folder.
    private static let resourcePlaceholderName =
        ".\(AgentFolderFixture.helperID)\(AgentFolderFixture.placeholderSuffix)"

    /// A hidden file with the exact name of the document after the dot, and
    /// no suffix. It is not a placeholder.
    private static let hiddenDocumentName = ".\(AgentDocumentPath.documentName)"

    /// A hidden file that holds the document name after a different prefix.
    /// It is not a placeholder.
    private static let prefixedDocumentName = ".old\(AgentDocumentPath.documentName)"

    /// The reason that the refusing file presenter gives.
    private static let refusalReason = "the presenter refuses the read"

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

        let catalog = try await AgentRegistry(layers: [folder.userLayer]).loadedCatalog()
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

        let catalog = try await AgentRegistry(layers: [folder.userLayer]).loadedCatalog()
        let diagnostic = try #require(catalog.diagnostics.first)

        #expect(catalog.defaultAgent == nil)
        #expect(catalog.diagnostics.count == 1)
        #expect(diagnostic.agent == AgentFolderFixture.defaultAgentID)
        #expect(diagnostic.message.contains(Self.notLocalText))
    }

    @Test(
        "a hidden root file that is not a placeholder of AGENT.md gives no agent and no diagnostic",
        arguments: [envFileName, resourcePlaceholderName])
    func hiddenRootFileIsNotAnAgent(name: String) async throws {
        let folder = try TemporaryLayer.make(holding: [name: ""])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [folder.userLayer]).loadedCatalog()

        #expect(catalog.definitions.isEmpty)
        #expect(catalog.diagnostics.isEmpty)
    }

    @Test("a hidden root file does not hide the agent of a lower layer with the same name")
    func hiddenRootFileDoesNotHideALowerAgent() async throws {
        let user = try TemporaryLayer.make(holding: [
            AgentDocumentPath.of(Self.envID): AgentFolderFixture.agentText(name: Self.envID)
        ])
        defer { try? user.delete() }
        let folder = try TemporaryLayer.make(holding: [Self.envFileName: ""])
        defer { try? folder.delete() }
        let userLayer = DotfolderStack.Layer(source: .user, root: user.root)

        let catalog = try await AgentRegistry(layers: [userLayer, folder.userLayer]).loadedCatalog()
        let definition = try #require(catalog.definition(named: Self.envID))

        #expect(catalog.definitions.map(\.id) == [Self.envID])
        #expect(catalog.diagnostics.isEmpty)
        #expect(definition.provenance.url == user.root.appendingPathComponent(AgentDocumentPath.of(Self.envID)))
    }

    @Test(
        "a hidden name in an agent folder that is not .AGENT.md.<suffix> gives no agent and no diagnostic",
        arguments: [hiddenDocumentName, prefixedDocumentName])
    func hiddenNameThatIsNotAPlaceholderIsAResource(name: String) async throws {
        let folder = try TemporaryLayer.make(holding: ["\(AgentFolderFixture.helperID)/\(name)": ""])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [folder.userLayer]).loadedCatalog()

        #expect(catalog.definitions.isEmpty)
        #expect(catalog.diagnostics.isEmpty)
    }

    @Test("a coordinated read that fails gives one skip with the cause of the failure")
    func failedCoordinationGivesItsCause() async throws {
        let id = AgentFolderFixture.helperID
        let path = AgentFolderFixture.documentPath(of: id)
        let folder = try TemporaryLayer.make(holding: [path: AgentFolderFixture.agentText(name: id)])
        defer { try? folder.delete() }
        let documentURL = folder.root.appendingPathComponent(path)
        let presenter = RefusingFilePresenter(url: documentURL, reason: Self.refusalReason)
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }

        let catalog = try await AgentRegistry(layers: [folder.userLayer]).loadedCatalog()
        let diagnostic = try #require(catalog.diagnostics.first)

        #expect(catalog.definitions.isEmpty)
        #expect(catalog.diagnostics.count == 1)
        #expect(diagnostic.agent == id)
        #expect(diagnostic.severity == .skip)
        #expect(diagnostic.message.contains(Self.refusalReason))
        #expect(!diagnostic.message.contains(Self.notLocalText))
        #expect(diagnostic.provenance.url == documentURL)
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

        let catalog = try await AgentRegistry(layers: [folder.userLayer]).loadedCatalog()
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

        let catalog = try await AgentRegistry(layers: [folder.userLayer]).loadedCatalog()
        let definition = try #require(catalog.definition(named: id))

        #expect(catalog.definitions.map(\.id) == [id])
        #expect(catalog.diagnostics.isEmpty)
        #expect(catalog.defaultAgent == nil)
        #expect(!definition.body.contains(Self.conflictBody))
    }
}

/// A file presenter that refuses each coordinated read of its file.
///
/// Before a coordinated read, the coordinator asks each presenter of the file
/// to save its changes. This presenter gives an error, thus the coordination
/// fails with that error, and the read does not run.
private final class RefusingFilePresenter: NSObject, NSFilePresenter {
    /// The error that the presenter gives.
    ///
    /// The coordinator keeps the user info of the error, thus the text goes
    /// in the user info, not in a `LocalizedError` property.
    private struct Refusal: CustomNSError {
        /// The text of the error.
        let reason: String

        /// The user info with the text of the error as its description.
        var errorUserInfo: [String: Any] {
            [NSLocalizedDescriptionKey: reason]
        }
    }

    /// The file that the presenter presents.
    let presentedItemURL: URL?

    /// The queue on which the coordinator sends the messages of the presenter.
    let presentedItemOperationQueue = OperationQueue()

    /// The text of the error that the presenter gives.
    private let reason: String

    /// Makes a presenter of one file.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - reason: The text of the error that the presenter gives.
    init(url: URL, reason: String) {
        presentedItemURL = url
        self.reason = reason
    }

    /// Refuses to save, thus the coordinated read fails.
    ///
    /// - Parameter completionHandler: The handler that gets the error.
    func savePresentedItemChanges(completionHandler: @escaping (Error?) -> Void) {
        completionHandler(Refusal(reason: reason))
    }
}
