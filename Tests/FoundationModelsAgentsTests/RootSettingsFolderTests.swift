import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins AG-10: the registry reads all its layers from the `DotfolderStack`
/// of the host, and there is no `agentFolders` input.
///
/// The root settings folder of a host is the `user` layer of the stack, and
/// the folder of the session is the `project` layer. Each local layer holds
/// its agents in the dotfolder form `agents/<id>/AGENT.md` and in the agent
/// folder form `<id>/AGENT.md`, with the root `AGENT.md` as the default
/// agent. A child folder whose name is not a valid id, for example
/// `_skills/`, is a settings folder and not an agent.
///
/// Each row writes a `TemporaryLayer` as the root, and a second one as the
/// folder of the session where the row needs it.
@Suite("Root settings folder")
struct RootSettingsFolderTests {
    /// The id of the agent that the root holds.
    private static let rootID = AgentFolderFixture.helperID

    /// The id of the agent that the root and the project layer both hold.
    private static let sharedID = "shared-agent"

    /// The id of the agent that the project layer of the CLI stack holds.
    private static let projectID = "project-agent"

    /// The position of the root layer in a stack `[user: root, project]`.
    private static let rootLayerIndex = 0

    /// The position of the project layer in a stack `[user: root, project]`.
    private static let projectLayerIndex = 1

    /// The dotfolder name of the CLI stack: `~/.config/agents/` and
    /// `<cwd>/.agents/`.
    private static let cliDotfolderName = "agents"

    /// The settings file at the root of the root settings folder.
    private static let settingsFileName = "config.yaml"

    /// The text of the settings file.
    private static let settingsText = "model: default\n"

    /// The instructions file at the root of the root settings folder.
    private static let instructionsFileName = "Instructions.md"

    /// The text of the instructions file.
    private static let instructionsText = "Be brief."

    /// The text of the diagnostic for a document that is not local yet.
    private static let notLocalText = "the agent document is not local yet"

    /// The name of a conflict copy of an agent document.
    private static let conflictCopyName = "AGENT 2.md"

    /// The body of the conflict copy, which the agent must not get.
    private static let conflictBody = "The body of the conflict copy."

    /// The name of the parameter that the source scan rejects.
    private static let removedParameterName = "agentFolders"

    /// The source directory, relative to the package root.
    private static let sourcesPath = "Sources"

    @Test("<root>/<id>/AGENT.md of the user layer is in the catalog of the stack")
    func rootAgentFolderLoads() async throws {
        let root = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: Self.rootID): AgentFolderFixture.agentText(name: Self.rootID)
        ])
        defer { try? root.delete() }
        let project = try TemporaryLayer.makeEmpty()
        defer { try? project.delete() }

        let registry = AgentRegistry(stack: DotfolderStack(layers: [root.userLayer, project.layer]))
        let catalog = try await registry.loadedCatalog()
        let definition = try #require(catalog.definition(named: Self.rootID))

        #expect(catalog.definitions.map(\.id) == [Self.rootID])
        #expect(catalog.diagnostics.isEmpty)
        #expect(definition.url == root.root.appendingPathComponent(AgentFolderFixture.documentPath(of: Self.rootID)))
        #expect(definition.provenance.layerIndex == Self.rootLayerIndex)
        #expect(registry.layers.map(\.root) == [root.root, project.root])
    }

    @Test(
        "the same id in the project layer wins over the root copy, with one advisory",
        arguments: [AgentDocumentPath.of(sharedID), AgentFolderFixture.documentPath(of: sharedID)])
    func projectCopyWins(projectPath: String) async throws {
        let rootPath = AgentFolderFixture.documentPath(of: Self.sharedID)
        let root = try TemporaryLayer.make(holding: [rootPath: AgentFolderFixture.agentText(name: Self.sharedID)])
        defer { try? root.delete() }
        let project = try TemporaryLayer.make(holding: [
            projectPath: AgentFolderFixture.agentText(name: Self.sharedID)
        ])
        defer { try? project.delete() }

        let catalog = try await AgentRegistry(layers: [root.userLayer, project.layer]).loadedCatalog()
        let definition = try #require(catalog.definition(named: Self.sharedID))
        let expected = AgentDiagnostic(
            severity: .advisory, agent: Self.sharedID, provenance: definition.provenance,
            message: AgentCatalogBuilder.hiddenCopyMessage(
                url: root.root.appendingPathComponent(rootPath), layerIndex: Self.rootLayerIndex))

        #expect(definition.url == project.root.appendingPathComponent(projectPath))
        #expect(definition.provenance.layerIndex == Self.projectLayerIndex)
        #expect(catalog.diagnostics == [expected])
    }

    @Test("<root>/AGENT.md of the user layer is the default agent")
    func rootDocumentIsTheDefaultAgent() async throws {
        let root = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName)
        ])
        defer { try? root.delete() }
        let project = try TemporaryLayer.makeEmpty()
        defer { try? project.delete() }

        let catalog = try await AgentRegistry(layers: [root.userLayer, project.layer]).loadedCatalog()
        let defaultAgent = try #require(catalog.defaultAgent)

        #expect(defaultAgent.id == AgentFolderFixture.defaultAgentID)
        #expect(defaultAgent.url == root.root.appendingPathComponent(AgentDocumentPath.documentName))
        #expect(catalog.diagnostics.isEmpty)
    }

    @Test(
        "a settings folder of the root gives no agent and no diagnostic, also with an AGENT.md in it",
        arguments: ["_skills", "_rules", AgentFolderFixture.partialsFolderName, ".git"])
    func settingsFolderIsNotAnAgent(folder: String) async throws {
        let root = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: Self.rootID): AgentFolderFixture.agentText(name: Self.rootID),
            AgentFolderFixture.documentPath(of: folder): AgentFolderFixture.agentText(name: folder),
            "\(folder)/\(AgentFolderFixture.partialName)": AgentFolderFixture.body,
            Self.settingsFileName: Self.settingsText,
            Self.instructionsFileName: Self.instructionsText
        ])
        defer { try? root.delete() }

        let catalog = try await AgentRegistry(layers: [root.userLayer]).loadedCatalog()

        #expect(catalog.definitions.map(\.id) == [Self.rootID])
        #expect(catalog.diagnostics.isEmpty)
    }

    @Test("a placeholder <root>/<id>/.AGENT.md.<suffix> gives the not-local skip")
    func rootPlaceholderGivesTheNotLocalSkip() async throws {
        let placeholderPath = "\(Self.rootID)/\(AgentFolderFixture.documentPlaceholderName)"
        let root = try TemporaryLayer.make(holding: [placeholderPath: ""])
        defer { try? root.delete() }

        let catalog = try await AgentRegistry(layers: [root.userLayer]).loadedCatalog()
        let diagnostic = try #require(catalog.diagnostics.first)

        #expect(catalog.definitions.isEmpty)
        #expect(catalog.diagnostics.count == 1)
        #expect(diagnostic.agent == Self.rootID)
        #expect(diagnostic.severity == .skip)
        #expect(diagnostic.message.contains(Self.notLocalText))
        #expect(diagnostic.provenance.url == root.root.appendingPathComponent(placeholderPath))
    }

    @Test("a conflict copy in <root>/<id>/ is a resource of the agent")
    func rootConflictCopyIsAResource() async throws {
        let root = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: Self.rootID): AgentFolderFixture.agentText(name: Self.rootID),
            "\(Self.rootID)/\(Self.conflictCopyName)":
                AgentFolderFixture.agentText(name: Self.rootID, body: Self.conflictBody)
        ])
        defer { try? root.delete() }

        let catalog = try await AgentRegistry(layers: [root.userLayer]).loadedCatalog()
        let definition = try #require(catalog.definition(named: Self.rootID))

        #expect(catalog.definitions.map(\.id) == [Self.rootID])
        #expect(catalog.diagnostics.isEmpty)
        #expect(!definition.body.contains(Self.conflictBody))
    }

    @Test("in one layer, <id>/AGENT.md wins over agents/<id>/AGENT.md, with one advisory")
    func agentFolderFormWinsInOneLayer() async throws {
        let hiddenPath = AgentDocumentPath.of(Self.rootID)
        let winnerPath = AgentFolderFixture.documentPath(of: Self.rootID)
        let root = try TemporaryLayer.make(holding: [
            hiddenPath: AgentFolderFixture.agentText(name: Self.rootID),
            winnerPath: AgentFolderFixture.agentText(name: Self.rootID)
        ])
        defer { try? root.delete() }

        let catalog = try await AgentRegistry(layers: [root.userLayer]).loadedCatalog()
        let definition = try #require(catalog.definition(named: Self.rootID))
        let expected = AgentDiagnostic(
            severity: .advisory, agent: Self.rootID, provenance: definition.provenance,
            message: AgentCatalogBuilder.hiddenCopyMessage(
                url: root.root.appendingPathComponent(hiddenPath), layerIndex: Self.rootLayerIndex))

        #expect(definition.url == root.root.appendingPathComponent(winnerPath))
        #expect(catalog.diagnostics == [expected])
    }

    @Test("the CLI stack gives each agents/<id>/AGENT.md of its user and project layers")
    func cliStackGivesTheDotfolderAgents() async throws {
        let user = try TemporaryLayer.make(holding: [
            AgentDocumentPath.of(Self.rootID): AgentFolderFixture.agentText(name: Self.rootID)
        ])
        defer { try? user.delete() }
        let workingDirectory = try TemporaryLayer.make(holding: [
            ".\(Self.cliDotfolderName)/\(AgentDocumentPath.of(Self.projectID))":
                AgentFolderFixture.agentText(name: Self.projectID)
        ])
        defer { try? workingDirectory.delete() }
        let stack = DotfolderStack(
            name: Self.cliDotfolderName, workingDirectory: workingDirectory.root, userDirectory: user.root,
            environment: [:])

        let registry = AgentRegistry(stack: stack)
        let catalog = try await registry.loadedCatalog()

        #expect(catalog.definitions.map(\.id) == [Self.rootID, Self.projectID])
        #expect(catalog.definitions.allSatisfy { $0.kind == .agentsFolder })
        #expect(catalog.diagnostics.isEmpty)
        #expect(registry.layers.map(\.root) == stack.layers.map(\.root))
    }

    @Test("no file under Sources names the removed agentFolders input")
    func noSourceNamesAgentFolders() throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.sourcesPath, matching: { line in line.contains(Self.removedParameterName) })

        #expect(offenders.isEmpty, "The registry has no agentFolders input; found: \(offenders)")
    }
}
