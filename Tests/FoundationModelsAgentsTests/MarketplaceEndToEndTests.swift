import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsSkills
import Marketplace
import MarketplaceFixtures
import Testing

/// Pins the marketplace agents end to end (plan.md §6, §14 M7, §15, §16).
///
/// Each row commits `Examples/agent-library/marketplace` into a local git
/// fixture repository, and installs the commit with a real
/// `MarketplaceStore`. One store feeds a `SkillsRegistry` and an
/// `AgentRegistry`. A run plays the scripted profile. No row uses the
/// network.
@Suite("Marketplace end to end")
struct MarketplaceEndToEndTests {
    /// The agent of the `code-tools` plugin.
    private static let securityReviewer = "security-reviewer"

    /// The agent of the `docs-tools` plugin. It has `model: sonnet`.
    private static let docWriter = "doc-writer"

    /// The plugin that holds `securityReviewer` and the `review` skill.
    private static let codeTools = "code-tools"

    /// The skill of the `code-tools` plugin.
    private static let reviewSkill = "review"

    /// The `model` value of `docWriter`. No slot of the profile matches it.
    private static let unmatchedModel = "sonnet"

    /// A text of the body of the `review` skill of the `code-tools` plugin.
    private static let reviewSkillText = "Review the code in these steps:"

    /// The file name of the partial that `securityReviewer` includes.
    private static let houseRulesName = "house-rules.md"

    /// The heading of the partial of the `code-tools` plugin.
    private static let codeToolsHouseRules = "## Code Tools House Rules"

    /// The name of the partials folder of a layer.
    private static let partialsFolderName = "_partials"

    /// The prompt of each run. It is also the key of the play of the run.
    private static let prompt = "marketplace-end-to-end-key: review the change"

    /// The final text of the play of a run.
    private static let finalText = "The review is done."

    /// The agent that the second commit adds to the `docs-tools` plugin.
    private static let addedAgent = "api-writer"

    /// The path of the file of `addedAgent` in the fixture repository.
    private static let addedAgentPath = "plugins/docs-tools/agents/\(addedAgent).md"

    /// The file of `addedAgent`.
    private static let addedAgentText = """
        ---
        name: \(addedAgent)
        description: Writes the documentation of an API.
        ---

        You write the documentation of the API of the prompt.
        """

    /// The agent of the tree source.
    private static let treeAgent = "tree-agent"

    /// The partial of the tree source.
    private static let treePartialName = "tree-rules.md"

    /// The text of the partial of the tree source.
    private static let treePartialText = "## Tree Rules"

    /// The skill of the tree source.
    private static let treeSkill = "tree-skill"

    /// The tree of a git source with no catalog: one agent that includes one
    /// partial of the source root, and one skill.
    ///
    /// - Returns: The tree, one entry for each path.
    private static func treeFiles() -> [String: GitFixtureRepository.Entry] {
        [
            agentPath(treeAgent): .file(
                """
                ---
                name: \(treeAgent)
                description: An agent of a tree source.
                ---

                You are an agent of a tree source.

                {% include "\(treePartialName)" %}
                """),
            partialPath(treePartialName): .file(treePartialText),
            "skills/\(skillPath(treeSkill))": .file(
                """
                ---
                name: \(treeSkill)
                description: A skill of a tree source.
                ---

                Do the steps of the tree skill.
                """)
        ]
    }

    /// A stack with no local layer: the catalog holds the marketplace agents
    /// only.
    private static let noLocalLayers = DotfolderStack(layers: [])

    /// A script with one play for ``prompt``.
    private static let script = ScriptedAgentScript([
        ScriptedAgentPlay(key: prompt, steps: [.finalText(finalText)])
    ])

    /// Makes an agent registry over the marketplace layers of `provider`
    /// and no local layer.
    ///
    /// - Parameter provider: The provider of the marketplace layers.
    /// - Returns: The registry. It is not loaded.
    private static func agentRegistry(over provider: some MarketplaceLayerProviding) -> AgentRegistry {
        AgentRegistry(marketplaces: provider, stack: noLocalLayers)
    }

    /// Makes a run harness whose agents and skills both come from the one
    /// store of `provider`.
    ///
    /// - Parameter provider: The provider of the marketplace layers.
    /// - Returns: The harness. Its registry is loaded.
    /// - Throws: The error of the harness.
    private static func harness(over provider: FixtureMarketplaceProvider) async throws -> AgentRunHarness {
        try await AgentRunHarness.make(
            script: script, registry: agentRegistry(over: provider),
            skills: SkillsRegistry(marketplaces: provider, stack: noLocalLayers))
    }

    /// Tells if a file is at `path` in the folder `root`.
    ///
    /// - Parameters:
    ///   - path: The path relative to `root`.
    ///   - root: The folder.
    /// - Returns: `true` when a file is at the path.
    private static func holdsFile(_ path: String, in root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    /// The path of the file of an agent, relative to a layer root.
    ///
    /// - Parameter id: The agent id.
    /// - Returns: `agents/<id>.md`.
    private static func agentPath(_ id: String) -> String {
        "\(MarketplaceLayer.agentsDirectoryName)/\(id).md"
    }

    /// The path of a partial, relative to a layer root.
    ///
    /// - Parameter name: The file name of the partial.
    /// - Returns: `_partials/<name>`.
    private static func partialPath(_ name: String) -> String {
        "\(partialsFolderName)/\(name)"
    }

    /// The path of the file of a skill, relative to a snapshot root.
    ///
    /// - Parameter id: The skill id.
    /// - Returns: `<id>/SKILL.md`.
    private static func skillPath(_ id: String) -> String {
        "\(id)/SKILL.md"
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

    @Test("one store with .all feeds a SkillsRegistry and an AgentRegistry")
    func oneStoreFeedsBothRegistries() async throws {
        let provider = try await FixtureMarketplaceProvider.make()
        defer { try? provider.delete() }

        let skills = SkillsRegistry(marketplaces: provider, stack: Self.noLocalLayers)
        let catalog = try await Self.agentRegistry(over: provider).loadedCatalog()

        #expect(catalog.definitions.map(\.id) == FixtureMarketplaceProvider.agentIDs)
        #expect(skills.metadata().map(\.id) == [Self.reviewSkill])
    }

    @Test(".plugins([code-tools]) gives security-reviewer only")
    func pluginsSelectionGivesThePluginAgents() async throws {
        let provider = try await FixtureMarketplaceProvider.make(select: .plugins([Self.codeTools]))
        defer { try? provider.delete() }

        let catalog = try await Self.agentRegistry(over: provider).loadedCatalog()

        #expect(catalog.definitions.map(\.id) == [Self.securityReviewer])
    }

    @Test(".skills([review]) gives the skill and no agents")
    func skillsSelectionGivesNoAgents() async throws {
        let provider = try await FixtureMarketplaceProvider.make(select: .skills([Self.reviewSkill]))
        defer { try? provider.delete() }

        let skills = SkillsRegistry(marketplaces: provider, stack: Self.noLocalLayers)
        let registry = Self.agentRegistry(over: provider)
        let catalog = try await registry.loadedCatalog()

        #expect(registry.marketplaceLayers.count == 1)
        #expect(catalog.definitions.isEmpty)
        #expect(skills.metadata().map(\.id) == [Self.reviewSkill])
    }

    @Test("the snapshot of a catalog source has the §6.1 shape, with the partials at <snapshot>/_partials/")
    func catalogSourceHasTheLayerShape() async throws {
        let provider = try await FixtureMarketplaceProvider.make()
        defer { try? provider.delete() }

        let root = try #require(provider.marketplaceLayers().first).layer.root
        let agentPaths = FixtureMarketplaceProvider.agentIDs.map(Self.agentPath)

        #expect(agentPaths.allSatisfy { Self.holdsFile($0, in: root) })
        #expect(Self.holdsFile(Self.skillPath(Self.reviewSkill), in: root))
        #expect(Self.holdsFile(Self.partialPath(Self.houseRulesName), in: root))
    }

    @Test("the snapshot of a tree source has the §6.1 shape, and its agent includes a root partial")
    func treeSourceHasTheLayerShape() async throws {
        let repository = try GitFixtureRepository()
        try repository.commit(files: Self.treeFiles())
        let fixture = try MarketplaceStoreFixture(sources: [MarketplaceSource(repository.url)])
        await fixture.store.start()
        let registry = Self.agentRegistry(over: fixture.store)
        let catalog = try await registry.loadedCatalog()

        let root = try #require(fixture.store.marketplaceLayers().first).layer.root
        let definition = try #require(catalog.definition(named: Self.treeAgent))
        let body = try AgentBodyRenderer(registry: registry).render(definition, prompt: Self.prompt)

        #expect(Self.holdsFile(Self.agentPath(Self.treeAgent), in: root))
        #expect(Self.holdsFile(Self.partialPath(Self.treePartialName), in: root))
        #expect(Self.holdsFile(Self.skillPath(Self.treeSkill), in: root))
        #expect(catalog.definitions.map(\.id) == [Self.treeAgent])
        #expect(body.contains(Self.treePartialText))
        withExtendedLifetime((repository, fixture)) {}
    }

    @Test("the body of security-reviewer includes house-rules.md from <layer root>/_partials/")
    func pluginBodyIncludesTheLayerPartial() async throws {
        let provider = try await FixtureMarketplaceProvider.make()
        defer { try? provider.delete() }
        let registry = Self.agentRegistry(over: provider)
        let catalog = try await registry.loadedCatalog()

        let definition = try #require(catalog.definition(named: Self.securityReviewer))
        let body = try AgentBodyRenderer(registry: registry).render(definition, prompt: Self.prompt)

        #expect(body.contains(Self.codeToolsHouseRules))
        #expect(!body.contains("{% include"))
    }

    @Test("a skills: preload of a skill of its own plugin works in a run")
    func skillsPreloadOfItsOwnPluginWorks() async throws {
        let provider = try await FixtureMarketplaceProvider.make()
        defer { try? provider.delete() }
        let harness = try await Self.harness(over: provider)
        defer { try? harness.delete() }

        let warnings = Self.catalogWarnings(of: Self.securityReviewer, in: harness)
        let run = try await harness.start(Self.securityReviewer, prompt: Self.prompt)
        let result = try await run.result()
        let instructions = try #require(try AgentRunTests.sidecar(of: run).configuration.instructions)

        #expect(warnings.isEmpty)
        #expect(result == Self.finalText)
        #expect(instructions.contains(Self.codeToolsHouseRules))
        #expect(instructions.contains(Self.reviewSkillText))
    }

    @Test("a model: sonnet marketplace file warns and runs on inherit")
    func unmatchedModelWarnsAndRunsOnInherit() async throws {
        let provider = try await FixtureMarketplaceProvider.make()
        defer { try? provider.delete() }
        let harness = try await Self.harness(over: provider)
        defer { try? harness.delete() }
        let inherited = harness.environment.defaultSlot

        let warnings = Self.catalogWarnings(of: Self.docWriter, in: harness)
        let run = try await harness.start(Self.docWriter, prompt: Self.prompt)

        let expected = ModelMatch.warning(model: Self.unmatchedModel, profile: harness.profile, inherited: inherited)
        #expect(warnings == [expected])
        #expect(run.slot == inherited)
        #expect(try await run.result() == Self.finalText)
    }

    @Test("a new commit and a store update give a new catalog through layerUpdates", .timeLimit(.minutes(1)))
    func newCommitGivesANewCatalog() async throws {
        let market = try FixtureMarketplaceProvider.makeUnstarted()
        let provider = market.provider
        defer { try? provider.delete() }
        await market.start()
        let registry = Self.agentRegistry(over: provider)
        try await registry.load()
        let reloads = registry.onReload

        let files = try FixtureMarketplaceProvider.fixtureTree()
            .merging([Self.addedAgentPath: .file(Self.addedAgentText)]) { _, added in added }
        let sha = try market.repository.commit(files: files)
        await market.fixture.store.update()

        let published = try #require(await reloads.first { $0.definition(named: Self.addedAgent) != nil })
        let expectedIDs = (FixtureMarketplaceProvider.agentIDs + [Self.addedAgent]).sorted()
        #expect(published.definitions.map(\.id) == expectedIDs)
        #expect(registry.marketplaceLayers.map(\.provenance.sha) == [sha])
    }
}
