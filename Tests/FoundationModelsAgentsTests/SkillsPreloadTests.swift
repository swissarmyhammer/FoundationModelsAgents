import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Pins the `skills:` preload of a run (plan.md §5, §8 step 3).
///
/// The skills registry has two layers: `Examples/agent-library/defaults/skills`
/// (the `review` skill) and the `skills/` folder of one temporary layer. The
/// temporary layer also holds the agents of the tests in its `agents/`
/// folder. Each run plays the scripted profile.
@Suite("Skills preload")
struct SkillsPreloadTests {
    /// The agents, the skills, and the registries of one test.
    private struct Library {
        /// The temporary layer that holds the agents and the written skills.
        let layer: TemporaryLayer

        /// The agent registry over `layer`. It is not loaded.
        let agents: AgentRegistry

        /// The skills registry over the fixture skills and the written skills.
        let skills: SkillsRegistry
    }

    /// The prompt of each run. It is also the key of the play.
    private static let prompt = "skills-preload-key: do the task"

    /// The final text of each play.
    private static let finalText = "The task is done."

    /// The name of the skills folder of a layer.
    private static let skillsFolderName = "skills"

    /// The fixture skill that each agent preloads.
    private static let review = "review"

    /// A text of the rendered body of the fixture `review` skill.
    private static let reviewBodyText = "Review this code and give specific feedback:"

    /// A written skill that the model can see.
    private static let checklist = "checklist"

    /// The body of `checklist`.
    private static let checklistBodyText = "Checklist skill: do each step in order."

    /// A written skill with `disable-model-invocation: true`.
    private static let deploy = "deploy"

    /// The body of `deploy`.
    private static let deployBodyText = "Deploy skill: ship the build."

    /// A written skill whose body the untrusted render refuses: it uses a
    /// filter.
    private static let broken = "broken"

    /// The body of `broken`.
    private static let brokenBodyText = "Name: {{ \"skill\"|uppercase }}."

    /// A skill name that no layer holds.
    private static let unknownSkill = "no-such-skill"

    /// The agent that preloads `review` only.
    private static let oneSkillAgent = "one-skill"

    /// The agent that preloads `checklist`, then `review`.
    private static let twoSkillsAgent = "two-skills"

    /// The agent that preloads `unknownSkill`, then `review`.
    private static let unknownSkillAgent = "unknown-skill"

    /// The agent that preloads `deploy`, then `review`.
    private static let hiddenSkillAgent = "hidden-skill"

    /// The agent that preloads `broken`.
    private static let brokenSkillAgent = "broken-skill"

    /// The agent that preloads no skill.
    private static let noSkillsAgent = "no-skills"

    /// The `skills` key of each written agent.
    private static let agentSkills = [
        oneSkillAgent: [review],
        twoSkillsAgent: [checklist, review],
        unknownSkillAgent: [unknownSkill, review],
        hiddenSkillAgent: [deploy, review],
        brokenSkillAgent: [broken],
        noSkillsAgent: []
    ]

    /// The body and the extra frontmatter lines of each written skill.
    private static let writtenSkills = [
        checklist: (body: checklistBodyText, extraKeys: ""),
        deploy: (body: deployBodyText, extraKeys: "disable-model-invocation: true"),
        broken: (body: brokenBodyText, extraKeys: "")
    ]

    /// The body of the written agent `agent`.
    ///
    /// - Parameter agent: The id of the agent.
    /// - Returns: The body text.
    private static func agentBodyText(of agent: String) -> String {
        "Body of the agent \(agent)."
    }

    /// Gives the text of a written agent file.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent.
    ///   - skills: The names of its `skills` key.
    /// - Returns: The text of the file.
    private static func agentFile(_ agent: String, skills: [String]) -> String {
        """
        ---
        name: \(agent)
        description: An agent of the skills preload tests.
        skills: [\(skills.joined(separator: ", "))]
        ---
        \(agentBodyText(of: agent))
        """
    }

    /// Gives the text of a written `SKILL.md` file.
    ///
    /// - Parameters:
    ///   - skill: The id of the skill.
    ///   - body: The body of the skill.
    ///   - extraKeys: More frontmatter lines, or the empty string.
    /// - Returns: The text of the file.
    private static func skillFile(_ skill: String, body: String, extraKeys: String) -> String {
        """
        ---
        name: \(skill)
        description: A skill of the skills preload tests.
        \(extraKeys)
        ---
        \(body)
        """
    }

    /// Writes the agents and the skills into a new temporary layer, and
    /// makes the registries over them.
    ///
    /// - Returns: The library.
    /// - Throws: The error of the file system.
    private static func makeLibrary() throws -> Library {
        let layer = try TemporaryLayer.makeEmpty()
        for (agent, skills) in agentSkills {
            try layer.write(agentFile(agent, skills: skills), at: "agents/\(agent).md")
        }
        for (skill, file) in writtenSkills {
            try layer.write(
                skillFile(skill, body: file.body, extraKeys: file.extraKeys),
                at: "\(skillsFolderName)/\(skill)/SKILL.md")
        }
        let skills = SkillsRegistry(layers: [
            DotfolderStack.Layer(
                source: .defaults,
                root: FixtureLibrary.defaultsDirectory.appendingPathComponent(skillsFolderName, isDirectory: true)),
            DotfolderStack.Layer(
                source: .project, root: layer.root.appendingPathComponent(skillsFolderName, isDirectory: true))
        ])
        return Library(layer: layer, agents: AgentRegistry(layers: [layer.layer]), skills: skills)
    }

    /// Makes a run harness over `library`.
    ///
    /// - Parameter library: The agents and the skills.
    /// - Returns: The harness. Its registry is loaded.
    /// - Throws: The error of the harness.
    private static func makeHarness(over library: Library) async throws -> AgentRunHarness {
        try await AgentRunHarness.make(
            script: ScriptedAgentScript([ScriptedAgentPlay(key: prompt, steps: [.finalText(finalText)])]),
            registry: library.agents,
            skills: library.skills)
    }

    /// Runs `agent` to its end, and gives the instructions of its session.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent.
    ///   - harness: The harness of the run.
    /// - Returns: The instructions of the session.
    /// - Throws: The error of the run, or of the read of the recording.
    private static func instructions(ofRunOf agent: String, in harness: AgentRunHarness) async throws -> String {
        let run = try await harness.start(agent, prompt: prompt)
        #expect(try await run.result() == finalText)
        return try #require(try AgentRunTests.sidecar(of: run).configuration.instructions)
    }

    /// Gives the start of each text of `texts` in `instructions`.
    ///
    /// - Parameters:
    ///   - texts: The texts to find.
    ///   - instructions: The instructions of a session.
    /// - Returns: The start of each text, in the order of `texts`.
    /// - Throws: The error of `#require` when a text is not in the
    ///   instructions.
    private static func starts(of texts: [String], in instructions: String) throws -> [String.Index] {
        try texts.map { text in try #require(instructions.range(of: text)).lowerBound }
    }

    /// Gives the warnings of `runner.catalog()` for one agent.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent.
    ///   - harness: The harness whose runner makes the catalog.
    /// - Returns: The messages of the warnings of the agent.
    private static func catalogWarnings(of agent: String, in harness: AgentRunHarness) -> [String] {
        harness.makeRunner().catalog().diagnostics
            .filter { $0.agent == agent && $0.severity == .warning }
            .map(\.message)
    }

    @Test("an agent with skills: [review] has the rendered review body after its own body")
    func oneSkillFollowsTheBody() async throws {
        let library = try Self.makeLibrary()
        defer { try? library.layer.delete() }
        let harness = try await Self.makeHarness(over: library)
        defer { try? harness.delete() }

        let instructions = try await Self.instructions(ofRunOf: Self.oneSkillAgent, in: harness)
        let starts = try Self.starts(
            of: [AgentRunHarness.agentsMdText, Self.agentBodyText(of: Self.oneSkillAgent), Self.reviewBodyText],
            in: instructions)

        #expect(starts == starts.sorted())
        #expect(!instructions.contains(AgentBodyRenderer.argumentsPlaceholder))
        #expect(Self.catalogWarnings(of: Self.oneSkillAgent, in: harness).isEmpty)
    }

    @Test("two skills appear in the order of the key")
    func twoSkillsKeepTheOrderOfTheKey() async throws {
        let library = try Self.makeLibrary()
        defer { try? library.layer.delete() }
        let harness = try await Self.makeHarness(over: library)
        defer { try? harness.delete() }

        let instructions = try await Self.instructions(ofRunOf: Self.twoSkillsAgent, in: harness)
        let starts = try Self.starts(
            of: [Self.agentBodyText(of: Self.twoSkillsAgent), Self.checklistBodyText, Self.reviewBodyText],
            in: instructions)

        #expect(starts == starts.sorted())
    }

    @Test("an unknown skill name gives a warning in runner.catalog(), and the run starts without it")
    func unknownSkillIsAWarningAndIsSkipped() async throws {
        let library = try Self.makeLibrary()
        defer { try? library.layer.delete() }
        let harness = try await Self.makeHarness(over: library)
        defer { try? harness.delete() }

        let warnings = Self.catalogWarnings(of: Self.unknownSkillAgent, in: harness)
        let instructions = try await Self.instructions(ofRunOf: Self.unknownSkillAgent, in: harness)

        #expect(warnings == [AgentSkillsPreload.unknownSkillFinding(Self.unknownSkill).message])
        #expect(warnings.allSatisfy { $0.contains(Self.unknownSkill) })
        #expect(instructions.contains(Self.reviewBodyText))
    }

    @Test("a skill with disable-model-invocation: true is skipped with a warning")
    func hiddenSkillIsAWarningAndIsSkipped() async throws {
        let library = try Self.makeLibrary()
        defer { try? library.layer.delete() }
        let harness = try await Self.makeHarness(over: library)
        defer { try? harness.delete() }

        let warnings = Self.catalogWarnings(of: Self.hiddenSkillAgent, in: harness)
        let instructions = try await Self.instructions(ofRunOf: Self.hiddenSkillAgent, in: harness)

        #expect(warnings == [AgentSkillsPreload.hiddenSkillFinding(Self.deploy).message])
        #expect(warnings.allSatisfy { $0.contains(Self.deploy) })
        #expect(!instructions.contains(Self.deployBodyText))
        #expect(instructions.contains(Self.reviewBodyText))
    }

    @Test("an agent with no skills key gets no skill text and no skill warning")
    func noSkillsGivesNoSkillText() async throws {
        let library = try Self.makeLibrary()
        defer { try? library.layer.delete() }
        let harness = try await Self.makeHarness(over: library)
        defer { try? harness.delete() }

        let instructions = try await Self.instructions(ofRunOf: Self.noSkillsAgent, in: harness)

        #expect(instructions.hasSuffix(Self.agentBodyText(of: Self.noSkillsAgent)))
        #expect(!instructions.contains(Self.reviewBodyText))
        #expect(Self.catalogWarnings(of: Self.noSkillsAgent, in: harness).isEmpty)
    }

    @Test("a preloaded skill whose body does not render fails the run before it makes a session")
    func skillRenderFailureFailsTheRun() async throws {
        let library = try Self.makeLibrary()
        defer { try? library.layer.delete() }
        let harness = try await Self.makeHarness(over: library)
        defer { try? harness.delete() }

        let run = try await harness.start(Self.brokenSkillAgent, prompt: Self.prompt)
        await #expect(throws: AgentRunFailure.self) {
            try await run.result()
        }
        let failure = try #require(Self.failure(of: run.state))

        #expect(Self.isSkillRenderFailure(failure))
        #expect(failure.reason.contains(Self.broken))
        #expect(run.recordingDirectory == nil)
        #expect(harness.script.prompts.isEmpty)
    }

    /// Gives the failure of a failed state.
    ///
    /// - Parameter state: The state of a run.
    /// - Returns: The failure, or `nil` when the state is not a failure.
    private static func failure(of state: AgentRunState) -> AgentRunFailure? {
        if case .failed(let failure) = state { return failure }
        return nil
    }

    /// `true` when `failure` is
    /// ``AgentRunFailure/skillRenderFailed(skill:description:)`` for the
    /// skill `broken`.
    ///
    /// - Parameter failure: The failure of a run.
    /// - Returns: `true` for that failure.
    private static func isSkillRenderFailure(_ failure: AgentRunFailure) -> Bool {
        if case .skillRenderFailed(skill: broken, description: _) = failure { return true }
        return false
    }
}
