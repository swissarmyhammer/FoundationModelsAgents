import Foundation
import FoundationModelsAgents
import FoundationModelsExtras
import Marketplace
import MarketplaceFixtures
import Testing

/// Each kind of agent source gives a live sub-agent (plan.md §15), and the
/// real `swissarmyhammer/skills` marketplace loads (plan.md §6.1, §16).
///
/// - A local agent file, a plugin of a git marketplace, and a plugin of a
///   `file://` folder each give an agent that a real model runs. The agent
///   answers with ``LiveSourceTree/answerWord``, thus the test sees that the
///   model got the body of that agent.
/// - The `swissarmyhammer/skills` marketplace comes over HTTPS: the git
///   transport of FoundationModelsExtras has no SSH. It gives its eight
///   agents, and its `_partials/sah-*.md` files are at the root of its layer.
///
/// Each live test uses the one resolved profile of ``LiveProfile/shared``.
/// The suite is serialized, thus one live run at a time uses the models.
@Suite("Live sources", .serialized, .timeLimit(LiveProfile.timeLimit))
struct LiveSourcesTests {
    /// The HTTPS URL of the `swissarmyhammer/skills` marketplace.
    private static let skillsMarketplaceURL = "https://github.com/swissarmyhammer/skills.git"

    /// The agent ids of the `swissarmyhammer/skills` marketplace, sorted.
    private static let skillsAgentIDs = [
        "committer", "double-check", "explorer", "general-purpose",
        "implementer", "planner", "reviewer", "tester"
    ]

    /// The number of `_partials/sah-*.md` files at the root of the layer of
    /// the `swissarmyhammer/skills` marketplace.
    private static let skillsPartialCount = 8

    /// The name of the partials folder at the root of a marketplace layer.
    private static let partialsFolderName = "_partials"

    /// The name prefix of each partial of the `swissarmyhammer/skills`
    /// marketplace.
    private static let skillsPartialPrefix = "sah-"

    /// The suffix of a partial file.
    private static let partialSuffix = ".md"

    @Test("a local agent file becomes a live sub-agent")
    func localFileBecomesALiveSubAgent() async throws {
        let layerRoot = try LiveSourceTree.writeTemporaryFolder(holding: LiveSourceTree.localLayerFiles)
        defer { try? FileManager.default.removeItem(at: layerRoot) }
        let registry = AgentRegistry(stack: DotfolderStack(layers: [.init(source: .project, root: layerRoot)]))

        let answer = try await Self.liveAnswer(of: LiveSourceTree.localAgentID, registry: registry)

        #expect(answer.definition.marketplaceLayer == nil)
        #expect(Self.holdsTheAnswerWord(answer.text), "The live answer was: \(answer.text)")
    }

    @Test("an agent of a git-marketplace plugin becomes a live sub-agent")
    func gitMarketplacePluginBecomesALiveSubAgent() async throws {
        let repository = try GitFixtureRepository()
        _ = try repository.commit(files: LiveSourceTree.marketplaceFiles.mapValues { .file($0) })
        let fixture = try MarketplaceStoreFixture(sources: [MarketplaceSource(repository.url)])
        await fixture.store.start()
        let registry = AgentRegistry(marketplaces: fixture.store, stack: DotfolderStack(layers: []))

        let answer = try await Self.liveAnswer(of: LiveSourceTree.pluginAgentID, registry: registry)

        #expect(answer.definition.marketplaceLayer != nil)
        #expect(Self.holdsTheAnswerWord(answer.text), "The live answer was: \(answer.text)")
        withExtendedLifetime((repository, fixture)) {}
    }

    @Test("an agent of a file:// folder plugin becomes a live sub-agent")
    func fileFolderPluginBecomesALiveSubAgent() async throws {
        let marketplaceRoot = try LiveSourceTree.writeTemporaryFolder(holding: LiveSourceTree.marketplaceFiles)
        defer { try? FileManager.default.removeItem(at: marketplaceRoot) }
        let source = MarketplaceSource(
            marketplaceRoot.absoluteString, path: LiveSourceTree.pluginPath, alias: LiveSourceTree.pluginName)
        let fixture = try MarketplaceStoreFixture(sources: [source])
        await fixture.store.start()
        let registry = AgentRegistry(marketplaces: fixture.store, stack: DotfolderStack(layers: []))

        let answer = try await Self.liveAnswer(of: LiveSourceTree.pluginAgentID, registry: registry)

        #expect(answer.definition.marketplaceLayer != nil)
        #expect(Self.holdsTheAnswerWord(answer.text), "The live answer was: \(answer.text)")
        withExtendedLifetime(fixture) {}
    }

    @Test("the swissarmyhammer/skills marketplace loads its agents, with its partials at the layer root")
    func skillsMarketplaceLoadsItsAgents() async throws {
        let fixture = try MarketplaceStoreFixture(sources: [MarketplaceSource(Self.skillsMarketplaceURL)])
        await fixture.store.start()
        let registry = AgentRegistry(marketplaces: fixture.store, stack: DotfolderStack(layers: []))
        try await registry.load()

        let marketplaceAgentIDs = registry.catalog().definitions
            .filter { $0.marketplaceLayer != nil }
            .map(\.id)
        #expect(marketplaceAgentIDs == Self.skillsAgentIDs)

        let layer = try #require(fixture.store.marketplaceLayers().first)
        let partialsFolder = layer.layer.root.appendingPathComponent(Self.partialsFolderName, isDirectory: true)
        let partials = try FileManager.default.contentsOfDirectory(atPath: partialsFolder.path)
            .filter { $0.hasPrefix(Self.skillsPartialPrefix) && $0.hasSuffix(Self.partialSuffix) }
        #expect(partials.count == Self.skillsPartialCount, "The partials at the layer root: \(partials.sorted())")
        withExtendedLifetime(fixture) {}
    }

    /// The agent that a live run used, and the final text of the run.
    private struct LiveAnswer {
        /// The definition of the agent in the loaded catalog.
        let definition: AgentDefinition

        /// The final text of the run.
        let text: String
    }

    /// Loads `registry`, starts the agent `id` on the live profile, and waits
    /// for the final text.
    ///
    /// The run is host-driven: `AgentRunner.start(_:prompt:)` starts it at
    /// depth 1, on the default slot. The working directory is a new
    /// temporary folder, which the call removes.
    ///
    /// - Parameters:
    ///   - id: The id of the agent.
    ///   - registry: The registry that holds the agent. The call loads it.
    /// - Returns: The definition of the agent and the final text of the run.
    /// - Throws: The error of the load, of the resolve, of the start, or of
    ///   the run. The call also fails the test when the catalog has no agent
    ///   `id`.
    private static func liveAnswer(of id: String, registry: AgentRegistry) async throws -> LiveAnswer {
        try await registry.load()
        let definition = try #require(registry.catalog().definition(named: id))
        let live = try await LiveProfile.shared.value
        let workingDirectory = try LiveSourceTree.makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let runner = live.makeRunner(registry: registry, workingDirectory: workingDirectory)
        let run = try await runner.start(id, prompt: LiveSourceTree.prompt)
        let text = try await run.result()
        await runner.stop()
        return LiveAnswer(definition: definition, text: text)
    }

    /// Tells whether a final text holds ``LiveSourceTree/answerWord``, in any
    /// case.
    ///
    /// - Parameter text: The final text of a run.
    /// - Returns: `true` when the text holds the answer word.
    private static func holdsTheAnswerWord(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains(LiveSourceTree.answerWord)
    }
}
