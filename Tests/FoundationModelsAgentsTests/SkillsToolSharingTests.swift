import Foundation
@testable import FoundationModelsAgents
import FoundationModels
import FoundationModelsSkills
import Testing

/// Pins the one skills registry of an environment.
///
/// The host gives one `SkillsRegistry`. The `skills` tool of the runs, the
/// `skills` tool of the host, and the `skills:` preload all read that
/// registry, with one visibility rule.
@Suite("One skills registry")
struct SkillsToolSharingTests {
    /// The name of the `skills` tool in the tool catalog.
    static let skillsToolName = "skills"

    /// The skill that the layer holds before the environment is made.
    static let firstSkill = "checklist"

    /// The skill that the test writes after the environment is made, or
    /// that the visibility rule of the test hides.
    static let laterSkill = "triage"

    /// The arguments of a `list skill` call.
    static let listCall = #"{"op": "list skill"}"#

    /// The arguments of a `search skill` call that matches ``firstSkill``.
    static let searchCall = #"{"op": "search skill", "query": "checklist"}"#

    /// The catalog character limit of the test of the limit. It is too small
    /// for the catalog of the test.
    static let smallCatalogCharacterLimit = 1

    /// Gives the text of a `SKILL.md` file.
    ///
    /// - Parameter skill: The id of the skill.
    /// - Returns: The text of the file.
    static func skillFile(_ skill: String) -> String {
        """
        ---
        name: \(skill)
        description: The \(skill) skill of the skills tool sharing tests.
        ---
        Body of the \(skill) skill.
        """
    }

    /// Gives the path of the `SKILL.md` file of a skill in a skills root.
    ///
    /// - Parameter skill: The id of the skill.
    /// - Returns: `<skill>/SKILL.md`.
    static func path(of skill: String) -> String {
        "\(skill)/SKILL.md"
    }

    /// Makes a skills root that holds `skills`.
    ///
    /// - Parameter skills: The ids of the skills to write.
    /// - Returns: The layer. Its root is the skills root.
    /// - Throws: The error of the file system.
    static func makeSkillsRoot(holding skills: [String]) throws -> TemporaryLayer {
        try TemporaryLayer.make(
            holding: Dictionary(uniqueKeysWithValues: skills.map { skill in (path(of: skill), skillFile(skill)) }))
    }

    /// Calls a skills tool, and gives its text.
    ///
    /// - Parameters:
    ///   - tool: The tool.
    ///   - json: The arguments, as JSON.
    /// - Returns: The output of the call.
    /// - Throws: The error of the arguments or of the call.
    static func call(_ tool: any Tool, with json: String) async throws -> String {
        let skillsTool = try #require(tool as? SkillsCatalogTool)
        return try await skillsTool.call(arguments: GeneratedContent(json: json))
    }

    @Test("the tool of the catalog, the tool of the host, and the preload read the one registry", .timeLimit(.minutes(1)))
    func oneRegistryReachesEachReader() async throws {
        let root = try Self.makeSkillsRoot(holding: [Self.firstSkill])
        defer { try? root.delete() }
        let skills = SkillsRegistry(roots: [root.root], watch: true)
        let reloads = try #require(skills.onReload)
        let environment = try await AgentEnvironment.make(
            profile: try await AgentEnvironmentTests.makeProfile(), skills: skills)

        try root.write(Self.skillFile(Self.laterSkill), at: Self.path(of: Self.laterSkill))
        for await metadata in reloads where metadata.contains(where: { $0.id == Self.laterSkill }) {
            break
        }
        let catalogTool = try #require(environment.tools.makeTool(named: Self.skillsToolName))

        #expect(try await Self.call(catalogTool, with: Self.listCall).contains(Self.laterSkill))
        #expect(try await Self.call(environment.skillsTool, with: Self.listCall).contains(Self.laterSkill))
        #expect(environment.skillsPreload.selection(of: [Self.laterSkill]).loaded == [Self.laterSkill])
    }

    @Test("the skills tool of the catalog is the skills tool of the environment")
    func catalogHoldsTheSkillsToolOfTheEnvironment() async throws {
        let root = try Self.makeSkillsRoot(holding: [Self.firstSkill])
        defer { try? root.delete() }
        let environment = try await AgentEnvironment.make(
            profile: try await AgentEnvironmentTests.makeProfile(), skills: SkillsRegistry(roots: [root.root]))

        let catalogTool = try #require(environment.tools.makeTool(named: Self.skillsToolName) as? SkillsCatalogTool)

        #expect(environment.skillsTool.name == Self.skillsToolName)
        #expect(catalogTool.description == environment.skillsTool.description)
        #expect(catalogTool.skillIDs == [Self.firstSkill])
    }

    @Test("a skill that the tool hides is not preloaded, and gives the hidden-skill warning")
    func hiddenSkillIsNotPreloaded() async throws {
        let root = try Self.makeSkillsRoot(holding: [Self.firstSkill, Self.laterSkill])
        defer { try? root.delete() }
        let environment = try await AgentEnvironment.make(
            profile: try await AgentEnvironmentTests.makeProfile(), skills: SkillsRegistry(roots: [root.root]),
            skillsVisibility: { metadata in metadata.id != Self.laterSkill })

        let selection = environment.skillsPreload.selection(of: [Self.laterSkill, Self.firstSkill])

        #expect(environment.skillsTool.skillIDs == [Self.firstSkill])
        #expect(selection.loaded == [Self.firstSkill])
        #expect(selection.findings.map(\.message) == [AgentSkillsPreload.hiddenSkillFinding(Self.laterSkill).message])
    }

    @Test("the catalog character limit reaches the skills tool")
    func catalogCharacterLimitReachesTheTool() async throws {
        let root = try Self.makeSkillsRoot(holding: [Self.firstSkill])
        defer { try? root.delete() }
        let profile = try await AgentEnvironmentTests.makeProfile()
        let skills = SkillsRegistry(roots: [root.root])

        let full = try await AgentEnvironment.make(profile: profile, skills: skills)
        let limited = try await AgentEnvironment.make(
            profile: profile, skills: skills, skillsCatalogCharacterLimit: Self.smallCatalogCharacterLimit)

        #expect(full.skillsTool.description.contains(Self.firstSkill))
        #expect(limited.skillsTool.description != full.skillsTool.description)
    }

    @Test("the skills selection model gets the search of the skills tool")
    func selectionModelGetsTheSearch() async throws {
        let root = try Self.makeSkillsRoot(holding: [Self.firstSkill])
        defer { try? root.delete() }
        let calls = SelectionProbeCalls()
        let environment = try await AgentEnvironment.make(
            profile: try await AgentEnvironmentTests.makeProfile(), skills: SkillsRegistry(roots: [root.root]),
            skillsSelectionModel: SelectionProbeModel(calls: calls))

        let answer = try await Self.call(environment.skillsTool, with: Self.searchCall)

        #expect(answer.contains(Self.firstSkill))
        #expect(calls.count > 0)
    }

    @Test("a host skills entry in the tool catalog stops the process")
    func hostSkillsEntryStopsTheProcess() async {
        await #expect(processExitsWith: .failure) {
            var tools = ToolCatalog()
            tools.register(Self.skillsToolName) { ProbeTool(name: Self.skillsToolName) }
            _ = try await AgentEnvironment.make(
                profile: try await AgentEnvironmentTests.makeProfile(), skills: SkillsRegistry(roots: []),
                tools: tools)
        }
    }
}
