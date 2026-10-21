import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the agent folder form of a local layer: the layout
/// `<root>/<id>/AGENT.md`, the default agent of `<root>/AGENT.md`, and the
/// precedence of the layers in the order of the stack, for example
/// `user < root settings folder < project`.
///
/// Each row writes a `TemporaryLayer` and gives its root as one local layer
/// with the source `user`.
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

    @Test("the layers of a registry are the layers of its stack, in the order of the stack")
    func registryLayersAreTheStackLayers() async throws {
        let stack = FixtureLibrary.stack()

        let registry = AgentRegistry(stack: stack)
        _ = try await registry.loadedCatalog()

        #expect(registry.layers.map(\.root) == stack.layers.map(\.root))
    }

    @Test("<root>/<id>/AGENT.md loads, and its id is the folder name")
    func agentFolderLoads() async throws {
        let id = AgentFolderFixture.helperID
        let folder = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: id): AgentFolderFixture.agentText(name: id)
        ])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [folder.userLayer]).loadedCatalog()
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

        let catalog = try await AgentRegistry(layers: [folder.userLayer]).loadedCatalog()
        let defaultAgent = try #require(catalog.defaultAgent)

        #expect(defaultAgent.id == AgentFolderFixture.defaultAgentID)
        #expect(AgentCatalog.defaultAgentID == AgentFolderFixture.defaultAgentID)
        #expect(defaultAgent.url == folder.root.appendingPathComponent(AgentDocumentPath.documentName))
        #expect(defaultAgent.folderURL.standardizedFileURL == folder.root.standardizedFileURL)
        #expect(catalog.diagnostics.isEmpty)
    }

    @Test("a layer with no root AGENT.md gives no default agent")
    func noRootDocumentGivesNoDefaultAgent() async throws {
        let id = AgentFolderFixture.helperID
        let folder = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: id): AgentFolderFixture.agentText(name: id)
        ])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [folder.userLayer]).loadedCatalog()

        #expect(catalog.defaultAgent == nil)
    }

    @Test("the root AGENT.md wins over <root>/default/AGENT.md, and the subfolder gives one warning")
    func rootDocumentWinsOverTheDefaultSubfolder() async throws {
        let subfolderPath = AgentFolderFixture.documentPath(of: AgentFolderFixture.defaultAgentID)
        let folder = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName),
            subfolderPath: AgentFolderFixture.agentText(name: AgentFolderFixture.defaultAgentID)
        ])
        defer { try? folder.delete() }

        let catalog = try await AgentRegistry(layers: [folder.userLayer]).loadedCatalog()
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

        let registry = AgentRegistry(layers: [folder.userLayer, project.layer])
        let catalog = try await registry.loadedCatalog()
        let defaultAgent = try #require(catalog.defaultAgent)
        let expected = AgentDiagnostic(
            code: .hiddenCopy, severity: .advisory, agent: AgentFolderFixture.defaultAgentID,
            provenance: defaultAgent.provenance,
            message: AgentCatalogBuilder.hiddenCopyMessage(url: hiddenURL, layerIndex: Self.firstFolderIndex))

        #expect(defaultAgent.layer.root == project.root)
        #expect(catalog.diagnostics == [expected])
    }

    @Test("an agent folder layer between the user layer and the project layer keeps that place")
    func agentFolderLayerKeepsItsPlaceInTheStack() async throws {
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

        let registry = AgentRegistry(layers: [user.userLayer, folder.userLayer, project.layer])
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
        let hiddenURL = user.root.appendingPathComponent(AgentDocumentPath.of(id))

        let catalog = try await AgentRegistry(layers: [user.userLayer, folder.userLayer]).loadedCatalog()
        let definition = try #require(catalog.definition(named: id))
        let expected = AgentDiagnostic(
            code: .hiddenCopy, severity: .advisory, agent: id, provenance: definition.provenance,
            message: AgentCatalogBuilder.hiddenCopyMessage(url: hiddenURL, layerIndex: Self.userLayerIndex))

        #expect(catalog.diagnostics == [expected])
    }

    @Test("of two layers with a root AGENT.md, the higher layer wins, with one advisory")
    func higherLayerWinsTheDefaultAgent() async throws {
        let first = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName)
        ])
        defer { try? first.delete() }
        let second = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName)
        ])
        defer { try? second.delete() }
        let hiddenURL = first.root.appendingPathComponent(AgentDocumentPath.documentName)

        let catalog = try await AgentRegistry(layers: [first.userLayer, second.userLayer]).loadedCatalog()
        let defaultAgent = try #require(catalog.defaultAgent)
        let expected = AgentDiagnostic(
            code: .hiddenCopy, severity: .advisory, agent: AgentFolderFixture.defaultAgentID,
            provenance: defaultAgent.provenance,
            message: AgentCatalogBuilder.hiddenCopyMessage(url: hiddenURL, layerIndex: Self.firstFolderIndex))

        #expect(defaultAgent.provenance.layerIndex == Self.secondFolderIndex)
        #expect(defaultAgent.layer.root == second.root)
        #expect(catalog.diagnostics == [expected])
    }

    @Test("a layer root that does not exist gives no agent and no diagnostic")
    func missingLayerRootGivesAnEmptyLayer() async throws {
        let container = try TemporaryLayer.makeEmpty()
        defer { try? container.delete() }
        let missing = container.container.appendingPathComponent(Self.missingFolderName, isDirectory: true)

        let catalog = try await AgentRegistry(layers: [DotfolderStack.Layer(source: .user, root: missing)])
            .loadedCatalog()

        #expect(catalog.definitions.isEmpty)
        #expect(catalog.diagnostics.isEmpty)
        #expect(catalog.defaultAgent == nil)
    }
}
