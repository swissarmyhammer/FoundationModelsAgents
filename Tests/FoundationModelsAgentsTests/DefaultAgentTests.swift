import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the default agent as the main session of a host.
///
/// The default agent (``AgentCatalog/defaultAgentID``) is the root
/// `AGENT.md` of a local layer, or `agents/default/AGENT.md` of a layer. A
/// host builds its main session from it with
/// ``AgentRunner/defaultAgentInstructions()``, and no run. Thus the `agents`
/// tool never offers it: the main session cannot give its task to a copy of
/// itself.
@Suite("Default agent")
struct DefaultAgentTests {
    /// The shared skills and runner of the main-session instructions tests.
    private typealias Fixture = SessionInstructionsFixture

    /// The agent next to the default agent in each layer.
    private static let helperID = AgentFolderFixture.helperID

    /// The body of the default agent of the lower layer.
    private static let userBody = "You are the main session of the user layer."

    /// The body of the default agent of the higher layer.
    private static let projectBody = "You are the main session of the project layer."

    /// A skill name that no layer holds.
    private static let unknownSkill = "no-such-skill"

    /// The text of the section that `tools.kanban.enabled` gates.
    private static let kanbanSection = "Use the kanban board."

    /// A body whose kanban section renders only when the template context
    /// turns the kanban tool on. `$ARGUMENTS` renders as empty text.
    private static let gatedBody =
        "Main session.[$ARGUMENTS]{% if tools.kanban.enabled %} \(kanbanSection){% endif %}"

    /// The template context with the kanban tool on.
    private static let kanbanOn: [String: TemplateValue] = [
        "tools": .dictionary(["kanban": .dictionary(["enabled": .bool(true)])])
    ]

    /// The template context with the kanban tool off.
    private static let kanbanOff: [String: TemplateValue] = [
        "tools": .dictionary(["kanban": .dictionary(["enabled": .bool(false)])])
    ]

    // MARK: - Fixtures

    /// Gives the text of a default agent file.
    ///
    /// - Parameters:
    ///   - body: The body.
    ///   - skills: The `skills` key. The default is no key.
    /// - Returns: The text of the file.
    private static func defaultAgentText(body: String, skills: [String] = []) -> String {
        AgentFolderFixture.agentText(name: AgentFolderFixture.displayName, body: body, skills: skills)
    }

    /// Makes a layer with a root `AGENT.md` and a visible helper agent.
    ///
    /// - Parameter defaultText: The text of the root `AGENT.md`.
    /// - Returns: The layer. The test deletes it.
    private static func makeLayer(defaultText: String) throws -> TemporaryLayer {
        try TemporaryLayer.make(holding: [
            "AGENT.md": defaultText,
            AgentFolderFixture.documentPath(of: helperID): AgentFolderFixture.agentText(name: helperID)
        ])
    }

    // MARK: - The agents tool never offers the default agent

    @Test("the default agent is neither model-visible nor user-invocable, with a valid description")
    func theDefaultAgentIsHidden() async throws {
        let layer = try Self.makeLayer(defaultText: Self.defaultAgentText(body: Self.projectBody))
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer])
        try await registry.load()

        let catalog = registry.catalog()
        let definition = try #require(catalog.defaultAgent)

        #expect(!definition.isModelVisible)
        #expect(!definition.isUserInvocable)
        #expect(catalog.modelVisible.map(\.id) == [Self.helperID])
        #expect(catalog.userInvocable.map(\.id) == [Self.helperID])
    }

    @Test("an agents/default/AGENT.md is hidden as the root AGENT.md is")
    func theDefaultFolderIsHidden() async throws {
        let layer = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: AgentCatalog.defaultAgentID): AgentFolderFixture.agentText(
                name: AgentCatalog.defaultAgentID),
            AgentFolderFixture.documentPath(of: Self.helperID): AgentFolderFixture.agentText(name: Self.helperID)
        ])
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer])
        try await registry.load()

        let definition = try #require(registry.catalog().defaultAgent)

        #expect(!definition.isModelVisible)
        #expect(!definition.isUserInvocable)
    }

    @Test("list agents and the description do not show the default agent, and start agent does not know it")
    func theAgentsToolNeverOffersTheDefaultAgent() async throws {
        let layer = try Self.makeLayer(defaultText: Self.defaultAgentText(body: Self.projectBody))
        defer { try? layer.delete() }
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }

        let listed = try await harness.call("list agents")
        let started = try await harness.call(
            "start agent", ["name": AgentCatalog.defaultAgentID, "prompt": "do the task"])

        #expect(listed.contains(Self.helperID))
        #expect(!listed.contains(AgentCatalog.defaultAgentID))
        #expect(!harness.tool.description.contains(AgentCatalog.defaultAgentID))
        #expect(started == AgentsToolText.unknownAgent(AgentCatalog.defaultAgentID, available: [Self.helperID]))
    }

    // MARK: - The template context

    @Test("a body renders with the template context of the registry")
    func theBodyRendersWithTheTemplateContext() async throws {
        let layer = try Self.makeLayer(defaultText: Self.defaultAgentText(body: Self.gatedBody))
        defer { try? layer.delete() }

        let on = try await Fixture.makeRunner(
            registry: AgentRegistry(layers: [layer.layer], templateContext: Self.kanbanOn))
        defer { try? on.harness.delete() }
        let off = try await Fixture.makeRunner(
            registry: AgentRegistry(layers: [layer.layer], templateContext: Self.kanbanOff))
        defer { try? off.harness.delete() }

        let onBody = try #require(try await on.runner.defaultAgentInstructions()).body
        let offBody = try #require(try await off.runner.defaultAgentInstructions()).body

        #expect(onBody == "Main session.[] \(Self.kanbanSection)")
        #expect(offBody == "Main session.[]")
    }

    // MARK: - The instructions of the default agent

    @Test("a catalog with no default agent gives no instructions")
    func noDefaultAgentGivesNil() async throws {
        let layer = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: Self.helperID): AgentFolderFixture.agentText(name: Self.helperID)
        ])
        defer { try? layer.delete() }
        let made = try await Fixture.makeRunner(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? made.harness.delete() }

        #expect(try await made.runner.defaultAgentInstructions() == nil)
    }

    @Test("the default agent of the higher layer wins")
    func theHigherLayerWins() async throws {
        let user = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: AgentCatalog.defaultAgentID): Self.defaultAgentText(
                body: Self.userBody)
        ])
        defer { try? user.delete() }
        let project = try Self.makeLayer(defaultText: Self.defaultAgentText(body: Self.projectBody))
        defer { try? project.delete() }
        let made = try await Fixture.makeRunner(
            registry: AgentRegistry(layers: [user.layer(source: .user), project.layer(source: .project)]))
        defer { try? made.harness.delete() }

        let instructions = try #require(try await made.runner.defaultAgentInstructions())

        #expect(instructions.definition.id == AgentCatalog.defaultAgentID)
        #expect(instructions.body == Self.projectBody)
        #expect(instructions.text == Self.projectBody)
    }

    @Test("the skills key preloads each visible skill in key order, and warns for the others")
    func theSkillsKeyPreloadsInOrder() async throws {
        let layer = try Self.makeLayer(
            defaultText: Self.defaultAgentText(
                body: Self.projectBody, skills: [Fixture.doTask, Self.unknownSkill, Fixture.deploy, Fixture.checklist]))
        defer { try? layer.delete() }
        let skills = try Fixture.makeSkills(in: layer)
        let made = try await Fixture.makeRunner(registry: AgentRegistry(layers: [layer.layer]), skills: skills)
        defer { try? made.harness.delete() }

        let instructions = try #require(try await made.runner.defaultAgentInstructions())

        #expect(instructions.skillBodies.count == 2)
        #expect(instructions.skillBodies.first?.contains(Fixture.doTaskBodyText) == true)
        #expect(instructions.skillBodies.last?.contains(Fixture.checklistBodyText) == true)
        #expect(
            instructions.diagnostics.map(\.message) == [
                AgentSkillsPreload.unknownSkillFinding(Self.unknownSkill).message,
                AgentSkillsPreload.hiddenSkillFinding(Fixture.deploy).message
            ])
        #expect(instructions.text.hasPrefix(Self.projectBody))
        let doTaskStart = try #require(instructions.text.range(of: Fixture.doTaskBodyText)).lowerBound
        let checklistStart = try #require(instructions.text.range(of: Fixture.checklistBodyText)).lowerBound
        #expect(doTaskStart < checklistStart)
    }
}

