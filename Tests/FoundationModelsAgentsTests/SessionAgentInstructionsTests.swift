import Foundation
@testable import FoundationModelsAgents
import Testing

/// Pins ``AgentRunner/sessionAgentInstructions(for:)``: the instructions of
/// any agent for a main session that the host makes with no run.
///
/// The body renders as the body of a run does, with `$ARGUMENTS` as empty
/// text, and the `skills:` key preloads its skills in the order of the key.
/// The definition can come from the catalog, or from
/// ``AgentRegistry/rootAgent(in:id:)`` of a folder that no layer of the
/// registry holds.
@Suite("Session agent instructions")
struct SessionAgentInstructionsTests {
    /// The shared skills and runner of the main-session instructions tests.
    private typealias Fixture = SessionInstructionsFixture

    /// The id of the named agent that is not the default agent.
    private static let reviewerID = "reviewer"

    /// The body of the named agent. `$ARGUMENTS` renders as empty text.
    private static let reviewerBody = "You review the change.[$ARGUMENTS]"

    /// The rendered body of the named agent.
    private static let renderedReviewerBody = "You review the change.[]"

    /// The body of the default agent.
    private static let defaultBody = "You are the main session."

    /// The body of the root `AGENT.md` of a folder that is not a layer.
    private static let folderBody = "You are the agent of the folder."

    /// The text of the partial at the root of the folder.
    private static let folderRules = "## Folder House Rules"

    // MARK: - Fixtures

    /// Makes a layer with the default agent, and the named agent with the
    /// `skills:` key `[Fixture.doTask, Fixture.checklist]`.
    ///
    /// - Returns: The layer. The test deletes it.
    private static func makeLayer() throws -> TemporaryLayer {
        try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(
                name: AgentFolderFixture.displayName, body: defaultBody),
            AgentFolderFixture.documentPath(of: reviewerID): AgentFolderFixture.agentText(
                name: reviewerID, body: reviewerBody, skills: [Fixture.doTask, Fixture.checklist])
        ])
    }

    /// Gives the instructions of the named agent of a layer from
    /// ``makeLayer()``, with the skills of ``SessionInstructionsFixture/makeSkills(in:)``.
    ///
    /// - Returns: The instructions.
    private static func reviewerInstructions() async throws -> SessionAgentInstructions {
        let layer = try makeLayer()
        defer { try? layer.delete() }
        let made = try await Fixture.makeRunner(
            registry: AgentRegistry(layers: [layer.layer]), skills: Fixture.makeSkills(in: layer))
        defer { try? made.harness.delete() }
        let reviewer = try #require(made.harness.registry.catalog().definition(named: reviewerID))
        return try await made.runner.sessionAgentInstructions(for: reviewer)
    }

    /// Gives the instructions of the root agent of a folder that no layer of
    /// the registry holds.
    ///
    /// - Parameter files: The files of the folder, by their path relative to
    ///   the folder.
    /// - Returns: The instructions.
    private static func folderInstructions(holding files: [String: String]) async throws -> SessionAgentInstructions {
        let folder = try TemporaryLayer.make(holding: files)
        defer { try? folder.delete() }
        let layer = try makeLayer()
        defer { try? layer.delete() }
        let made = try await Fixture.makeRunner(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? made.harness.delete() }
        let definition = try #require(AgentRegistry.rootAgent(in: folder.root, id: reviewerID).definition)
        return try await made.runner.sessionAgentInstructions(for: definition)
    }

    // MARK: - A named agent

    @Test("a named agent that is not default gives its rendered body")
    func aNamedAgentGivesItsBody() async throws {
        let instructions = try await Self.reviewerInstructions()

        #expect(instructions.body == Self.renderedReviewerBody)
    }

    @Test("a named agent that is not default gives the bodies of its skills preload, in key order")
    func aNamedAgentGivesItsSkillsInOrder() async throws {
        let instructions = try await Self.reviewerInstructions()

        let skillTexts = [Fixture.doTaskBodyText, Fixture.checklistBodyText]
        let order = instructions.skillBodies.map { body in skillTexts.first { body.contains($0) } }

        #expect(order == skillTexts)
    }

    // MARK: - A definition from rootAgent(in:)

    @Test("a definition from rootAgent(in:) of a folder that is not a layer renders")
    func aRootAgentOfAFolderRenders() async throws {
        let instructions = try await Self.folderInstructions(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(
                name: AgentFolderFixture.displayName, body: Self.folderBody)
        ])

        #expect(instructions.body == Self.folderBody)
    }

    @Test("a definition from rootAgent(in:) includes a partial of its folder")
    func aRootAgentOfAFolderIncludesItsPartial() async throws {
        let instructions = try await Self.folderInstructions(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.includingAgentText(
                name: AgentFolderFixture.displayName),
            AgentFolderFixture.partialPath(in: nil): Self.folderRules
        ])

        #expect(instructions.body.contains(Self.folderRules))
    }

    // MARK: - The default agent

    @Test("defaultAgentInstructions() gives the instructions of the default agent of the catalog")
    func theDefaultAgentInstructionsAreUnchanged() async throws {
        let layer = try Self.makeLayer()
        defer { try? layer.delete() }
        let made = try await Fixture.makeRunner(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? made.harness.delete() }

        let instructions: SessionAgentInstructions? = try await made.runner.defaultAgentInstructions()

        #expect(instructions?.text == Self.defaultBody)
    }
}
