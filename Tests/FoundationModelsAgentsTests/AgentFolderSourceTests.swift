import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the agent-folder source of `AgentRegistry`: the optional
/// `agentFolders` input, the layout `<url>/<id>/AGENT.md`, the default agent
/// of `<url>/AGENT.md`, and the precedence
/// `marketplace < defaults < user < agent folders < project`.
///
/// Each row writes a `TemporaryLayer` and gives its root as one agent-folder
/// URL.
@Suite("Agent folder source")
struct AgentFolderSourceTests {
    /// The id of the agent that each layer of the precedence rows holds.
    private static let sharedID = "shared-agent"

    /// The id of the agent that the user layer and the agent folder hold.
    private static let userAndFolderID = "folder-agent"

    /// The position of the user layer in the precedence rows.
    private static let userLayerIndex = 0

    /// The position of the agent folder in the precedence rows.
    private static let folderLayerIndex = 1

    /// The position of the project layer in the precedence rows.
    private static let projectLayerIndex = 2

    /// The position of the first of two agent folders, with no other layer.
    private static let firstFolderIndex = 0

    /// The position of the second of two agent folders, with no other layer.
    private static let secondFolderIndex = 1

    /// The name of a folder that no test makes.
    private static let missingFolderName = "missing-agents"

    /// The text that the warning for a hidden `default/` subfolder holds.
    private static let rootDocumentWins = "the root \(AgentDocumentPath.documentName)"

    @Test("a registry with no agent folder gives the same catalog and layers as before")
    func noAgentFolderGivesTheCurrentCatalog() async throws {
        let stack = FixtureLibrary.stack()
        let plain = try await AgentRegistry(stack: stack).loadedCatalog()
        let registry = AgentRegistry(stack: stack, agentFolders: [])
        let empty = try await registry.loadedCatalog()

        #expect(empty.definitions.map(\.id) == plain.definitions.map(\.id))
        #expect(empty.diagnostics == plain.diagnostics)
        #expect(registry.layers.map(\.root) == stack.layers.map(\.root))
        #expect(registry.agentFolders.isEmpty)
    }

    @Test("<url>/<id>/AGENT.md loads, and its id is the folder name")
    func agentFolderLoads() async throws {
        let id = AgentFolderFixture.helperID
        let folder = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: id): AgentFolderFixture.agentText(name: id)
        ])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [], agentFolders: [folder.root]).loadedCatalog()
        let definition = try #require(catalog.definition(named: id))

        #expect(catalog.definitions.map(\.id) == [id])
        #expect(catalog.diagnostics.isEmpty)
        #expect(definition.url == folder.root.appendingPathComponent(AgentFolderFixture.documentPath(of: id)))
        #expect(definition.folderURL == folder.root.appendingPathComponent(id))
        #expect(definition.layer.source == .user)
    }

    @Test("the root AGENT.md is the default agent, and its name is a display name")
    func rootDocumentIsTheDefaultAgent() async throws {
        let folder = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName)
        ])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [], agentFolders: [folder.root]).loadedCatalog()
        let defaultAgent = try #require(catalog.defaultAgent)

        #expect(defaultAgent.id == AgentFolderFixture.defaultAgentID)
        #expect(AgentCatalog.defaultAgentID == AgentFolderFixture.defaultAgentID)
        #expect(defaultAgent.url == folder.root.appendingPathComponent(AgentDocumentPath.documentName))
        #expect(defaultAgent.folderURL.standardizedFileURL == folder.root.standardizedFileURL)
        #expect(catalog.diagnostics.isEmpty)
    }

    @Test("a source with no root AGENT.md gives no default agent")
    func noRootDocumentGivesNoDefaultAgent() async throws {
        let id = AgentFolderFixture.helperID
        let folder = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: id): AgentFolderFixture.agentText(name: id)
        ])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [], agentFolders: [folder.root]).loadedCatalog()

        #expect(catalog.defaultAgent == nil)
    }

    @Test("the root AGENT.md wins over <url>/default/AGENT.md, and the subfolder gives one warning")
    func rootDocumentWinsOverTheDefaultSubfolder() async throws {
        let subfolderPath = AgentFolderFixture.documentPath(of: AgentFolderFixture.defaultAgentID)
        let folder = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName),
            subfolderPath: AgentFolderFixture.agentText(name: AgentFolderFixture.defaultAgentID)
        ])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [], agentFolders: [folder.root]).loadedCatalog()
        let defaultAgent = try #require(catalog.defaultAgent)
        let warning = try #require(catalog.diagnostics.first)

        #expect(defaultAgent.url == folder.root.appendingPathComponent(AgentDocumentPath.documentName))
        #expect(catalog.diagnostics.count == 1)
        #expect(warning.severity == .warning)
        #expect(warning.agent == AgentFolderFixture.defaultAgentID)
        #expect(warning.provenance.url == folder.root.appendingPathComponent(subfolderPath))
        #expect(warning.message.contains(Self.rootDocumentWins))
    }

    @Test("a project agents/default/AGENT.md wins over the root AGENT.md, with one advisory")
    func projectDefaultAgentWins() async throws {
        let project = try TemporaryLayer.make(holding: [
            AgentDocumentPath.of(AgentFolderFixture.defaultAgentID):
                AgentFolderFixture.agentText(name: AgentFolderFixture.defaultAgentID)
        ])
        defer { try? project.delete() }
        let folder = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName)
        ])
        defer { try? folder.delete() }
        let hiddenURL = folder.root.appendingPathComponent(AgentDocumentPath.documentName)

        let registry = AgentRegistry(layers: [project.layer], agentFolders: [folder.root])
        let catalog = try await registry.loadedCatalog()
        let defaultAgent = try #require(catalog.defaultAgent)
        let expected = AgentDiagnostic(
            severity: .advisory, agent: AgentFolderFixture.defaultAgentID, provenance: defaultAgent.provenance,
            message: AgentCatalogBuilder.hiddenCopyMessage(url: hiddenURL, layerIndex: Self.firstFolderIndex))

        #expect(defaultAgent.layer.root == project.root)
        #expect(catalog.diagnostics == [expected])
    }

    @Test("the agent folders are above the user layer and below the project layer")
    func agentFoldersAreBetweenUserAndProject() async throws {
        let user = try TemporaryLayer.make(holding: [
            AgentDocumentPath.of(Self.sharedID): AgentFolderFixture.agentText(name: Self.sharedID),
            AgentDocumentPath.of(Self.userAndFolderID): AgentFolderFixture.agentText(name: Self.userAndFolderID)
        ])
        defer { try? user.delete() }
        let folder = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: Self.sharedID): AgentFolderFixture.agentText(name: Self.sharedID),
            AgentFolderFixture.documentPath(of: Self.userAndFolderID):
                AgentFolderFixture.agentText(name: Self.userAndFolderID)
        ])
        defer { try? folder.delete() }
        let project = try TemporaryLayer.make(holding: [
            AgentDocumentPath.of(Self.sharedID): AgentFolderFixture.agentText(name: Self.sharedID)
        ])
        defer { try? project.delete() }
        let userLayer = DotfolderStack.Layer(source: .user, root: user.root)

        let registry = AgentRegistry(layers: [userLayer, project.layer], agentFolders: [folder.root])
        let catalog = try await registry.loadedCatalog()
        let shared = try #require(catalog.definition(named: Self.sharedID))
        let userAndFolder = try #require(catalog.definition(named: Self.userAndFolderID))

        #expect(registry.layers.map(\.root) == [user.root, folder.root, project.root])
        #expect(shared.provenance.layerIndex == Self.projectLayerIndex)
        #expect(userAndFolder.provenance.layerIndex == Self.folderLayerIndex)
        #expect(userAndFolder.url == folder.root.appendingPathComponent(
            AgentFolderFixture.documentPath(of: Self.userAndFolderID)))
    }

    @Test("a copy in a lower layer that an agent folder hides gives the hidden-copy advisory")
    func agentFolderCopyHidesTheUserCopy() async throws {
        let id = AgentFolderFixture.helperID
        let user = try TemporaryLayer.make(holding: [AgentDocumentPath.of(id): AgentFolderFixture.agentText(name: id)])
        defer { try? user.delete() }
        let folder = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: id): AgentFolderFixture.agentText(name: id)
        ])
        defer { try? folder.delete() }
        let userLayer = DotfolderStack.Layer(source: .user, root: user.root)
        let hiddenURL = user.root.appendingPathComponent(AgentDocumentPath.of(id))

        let catalog = try await AgentRegistry(layers: [userLayer], agentFolders: [folder.root]).loadedCatalog()
        let definition = try #require(catalog.definition(named: id))
        let expected = AgentDiagnostic(
            severity: .advisory, agent: id, provenance: definition.provenance,
            message: AgentCatalogBuilder.hiddenCopyMessage(url: hiddenURL, layerIndex: Self.userLayerIndex))

        #expect(catalog.diagnostics == [expected])
    }

    @Test("of two agent folders with a root AGENT.md, the later URL wins, with one advisory")
    func laterAgentFolderWinsTheDefaultAgent() async throws {
        let first = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName)
        ])
        defer { try? first.delete() }
        let second = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName)
        ])
        defer { try? second.delete() }
        let hiddenURL = first.root.appendingPathComponent(AgentDocumentPath.documentName)

        let catalog = try await AgentRegistry(layers: [], agentFolders: [first.root, second.root]).loadedCatalog()
        let defaultAgent = try #require(catalog.defaultAgent)
        let expected = AgentDiagnostic(
            severity: .advisory, agent: AgentFolderFixture.defaultAgentID, provenance: defaultAgent.provenance,
            message: AgentCatalogBuilder.hiddenCopyMessage(url: hiddenURL, layerIndex: Self.firstFolderIndex))

        #expect(defaultAgent.provenance.layerIndex == Self.secondFolderIndex)
        #expect(defaultAgent.layer.root == second.root)
        #expect(catalog.diagnostics == [expected])
    }

    @Test("an agent-folder URL that does not exist gives no agent and no diagnostic")
    func missingAgentFolderGivesAnEmptySource() async throws {
        let container = try TemporaryLayer.makeEmpty()
        defer { try? container.delete() }
        let missing = container.container.appendingPathComponent(Self.missingFolderName, isDirectory: true)

        let catalog = try await AgentRegistry(layers: [], agentFolders: [missing]).loadedCatalog()

        #expect(catalog.definitions.isEmpty)
        #expect(catalog.diagnostics.isEmpty)
        #expect(catalog.defaultAgent == nil)
    }
}
