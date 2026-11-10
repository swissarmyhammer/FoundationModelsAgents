import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsSkills

/// The skills and the runner that the tests of the main-session instructions
/// share.
///
/// ``DefaultAgentTests`` and ``SessionAgentInstructionsTests`` render the
/// instructions of an agent for a main session with no run. Both suites use
/// this one source for the skills of a layer and for the runner, thus a
/// change to the harness setup changes one helper.
enum SessionInstructionsFixture {
    /// The name of the skills folder of a layer.
    static let skillsFolderName = "skills"

    /// A written skill that the model can see.
    static let doTask = "do-task"

    /// The body of `doTask`.
    static let doTaskBodyText = "Do-task skill: plan, then do each step."

    /// A written skill that the model can see.
    static let checklist = "checklist"

    /// The body of `checklist`.
    static let checklistBodyText = "Checklist skill: check each step."

    /// A written skill with `disable-model-invocation: true`.
    static let deploy = "deploy"

    /// The body of `deploy`.
    static let deployBodyText = "Deploy skill."

    /// The frontmatter line that hides a skill from the model.
    static let hiddenKey = "disable-model-invocation: true"

    /// Gives the text of a skill file.
    ///
    /// - Parameters:
    ///   - skill: The id of the skill.
    ///   - body: The body.
    ///   - extraKeys: More frontmatter lines.
    /// - Returns: The text of the file.
    static func skillText(_ skill: String, body: String, extraKeys: String = "") -> String {
        """
        ---
        name: \(skill)
        description: A skill of the main-session instructions tests.
        \(extraKeys)
        ---
        \(body)
        """
    }

    /// Gives the text of an agent file with a `skills:` key.
    ///
    /// - Parameters:
    ///   - name: The value of the `name` key.
    ///   - body: The body.
    ///   - skills: The `skills` key.
    /// - Returns: The text of the file.
    static func agentText(name: String, body: String, skills: [String]) -> String {
        """
        ---
        name: \(name)
        description: \(AgentFolderFixture.description)
        skills: [\(skills.joined(separator: ", "))]
        ---
        \(body)
        """
    }

    /// Makes a skills registry over the `skills/` folder of `layer`, with
    /// `doTask`, `checklist` and the hidden `deploy`.
    ///
    /// - Parameter layer: The layer that holds the skills.
    /// - Returns: The skills registry.
    static func makeSkills(in layer: TemporaryLayer) throws -> SkillsRegistry {
        try layer.write(skillText(doTask, body: doTaskBodyText), at: skillPath(of: doTask))
        try layer.write(skillText(checklist, body: checklistBodyText), at: skillPath(of: checklist))
        try layer.write(skillText(deploy, body: deployBodyText, extraKeys: hiddenKey), at: skillPath(of: deploy))
        return SkillsRegistry(layers: [
            DotfolderStack.Layer(
                source: .project, root: layer.root.appendingPathComponent(skillsFolderName, isDirectory: true))
        ], mode: .open)
    }

    /// Makes a runner over `registry` and `skills`, with no play.
    ///
    /// - Parameters:
    ///   - registry: The agent registry. The harness loads it.
    ///   - skills: The skills registry.
    /// - Returns: The harness and its runner. The test deletes the harness.
    static func makeRunner(
        registry: AgentRegistry, skills: SkillsRegistry = SkillsRegistry.makeEmpty()
    ) async throws -> (harness: AgentRunHarness, runner: AgentRunner) {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([]), registry: registry, skills: skills)
        return (harness, harness.makeRunner())
    }

    /// Gives the path of the skill file of `skill`, relative to the layer
    /// root.
    ///
    /// - Parameter skill: The id of the skill.
    /// - Returns: `skills/<skill>/SKILL.md`.
    private static func skillPath(of skill: String) -> String {
        "\(skillsFolderName)/\(skill)/SKILL.md"
    }
}
