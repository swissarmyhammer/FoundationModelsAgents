import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsSkills
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

    /// The name of the skills folder of a layer.
    private static let skillsFolderName = "skills"

    /// The first skill of the `skills:` key.
    private static let doTask = "do-task"

    /// The body of `doTask`.
    private static let doTaskBodyText = "Do-task skill: plan, then do each step."

    /// The second skill of the `skills:` key.
    private static let checklist = "checklist"

    /// The body of `checklist`.
    private static let checklistBodyText = "Checklist skill: check each step."

    // MARK: - Fixtures

    /// Gives the text of an agent file with a `skills:` key.
    ///
    /// - Parameters:
    ///   - name: The value of the `name` key.
    ///   - body: The body.
    ///   - skills: The `skills` key.
    /// - Returns: The text of the file.
    private static func agentText(name: String, body: String, skills: [String]) -> String {
        """
        ---
        name: \(name)
        description: \(AgentFolderFixture.description)
        skills: [\(skills.joined(separator: ", "))]
        ---
        \(body)
        """
    }

    /// Gives the text of a skill file.
    ///
    /// - Parameters:
    ///   - skill: The id of the skill.
    ///   - body: The body.
    /// - Returns: The text of the file.
    private static func skillText(_ skill: String, body: String) -> String {
        """
        ---
        name: \(skill)
        description: A skill of the session agent instructions tests.
        ---
        \(body)
        """
    }

    /// Makes a layer with the default agent, and the named agent with the
    /// `skills:` key `[doTask, checklist]`.
    ///
    /// - Returns: The layer. The test deletes it.
    private static func makeLayer() throws -> TemporaryLayer {
        try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: agentText(
                name: AgentFolderFixture.displayName, body: defaultBody, skills: []),
            AgentFolderFixture.documentPath(of: reviewerID): agentText(
                name: reviewerID, body: reviewerBody, skills: [doTask, checklist])
        ])
    }

    /// Makes a skills registry over the `skills/` folder of `layer`, with
    /// `doTask` and `checklist`.
    ///
    /// - Parameter layer: The layer that holds the skills.
    /// - Returns: The skills registry.
    private static func makeSkills(in layer: TemporaryLayer) throws -> SkillsRegistry {
        try layer.write(skillText(doTask, body: doTaskBodyText), at: "\(skillsFolderName)/\(doTask)/SKILL.md")
        try layer.write(
            skillText(checklist, body: checklistBodyText), at: "\(skillsFolderName)/\(checklist)/SKILL.md")
        return SkillsRegistry(layers: [
            DotfolderStack.Layer(
                source: .project, root: layer.root.appendingPathComponent(skillsFolderName, isDirectory: true))
        ])
    }

    /// Makes a runner over `registry` and `skills`, with no play.
    ///
    /// - Parameters:
    ///   - registry: The agent registry. The harness loads it.
    ///   - skills: The skills registry.
    /// - Returns: The harness and its runner. The test deletes the harness.
    private static func makeRunner(
        registry: AgentRegistry, skills: SkillsRegistry = SkillsRegistry(roots: [])
    ) async throws -> (harness: AgentRunHarness, runner: AgentRunner) {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([]), registry: registry, skills: skills)
        return (harness, harness.makeRunner())
    }

    /// Gives the instructions of the named agent of a layer from
    /// ``makeLayer()``, with the skills of ``makeSkills(in:)``.
    ///
    /// - Returns: The instructions.
    private static func reviewerInstructions() async throws -> SessionAgentInstructions {
        let layer = try makeLayer()
        defer { try? layer.delete() }
        let made = try await makeRunner(registry: AgentRegistry(layers: [layer.layer]), skills: makeSkills(in: layer))
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
        let made = try await makeRunner(registry: AgentRegistry(layers: [layer.layer]))
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

        let skillTexts = [Self.doTaskBodyText, Self.checklistBodyText]
        let order = instructions.skillBodies.map { body in skillTexts.first { body.contains($0) } }

        #expect(order == skillTexts)
    }

    // MARK: - A definition from rootAgent(in:)

    @Test("a definition from rootAgent(in:) of a folder that is not a layer renders")
    func aRootAgentOfAFolderRenders() async throws {
        let instructions = try await Self.folderInstructions(holding: [
            AgentDocumentPath.documentName: Self.agentText(
                name: AgentFolderFixture.displayName, body: Self.folderBody, skills: [])
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
        let made = try await Self.makeRunner(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? made.harness.delete() }

        let instructions: SessionAgentInstructions? = try await made.runner.defaultAgentInstructions()

        #expect(instructions?.text == Self.defaultBody)
    }
}
