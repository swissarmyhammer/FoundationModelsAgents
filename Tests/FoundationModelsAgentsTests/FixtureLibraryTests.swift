import Foundation
import FoundationModelsExtras
import Testing

/// Pins the fixture library at `Examples/agent-library` (plan.md §13).
///
/// The suite makes sure that each fixture file exists, that
/// `FixtureLibrary.stack()` gives the three local layers in order, that the
/// fixture marketplace catalog decodes as JSON, and that the marketplace
/// agents hold the keys that later suites use.
@Suite("Fixture library")
struct FixtureLibraryTests {
    /// The file names of the `broken/agents/` fixtures, each with one defect.
    private static let brokenFileNames = [
        "bad-colon-description.md",
        "missing-description.md",
        "bad-name.md",
        "Bad_Name.md",
        "no-frontmatter.md",
        "unknown-model.md",
        "unknown-disallowed-tool.md"
    ]

    /// The URL of each fixture file: the layer files, then the broken files.
    private static let expectedFiles = layerFiles.map(FixtureLibrary.url)
        + brokenFileNames.map { FixtureLibrary.brokenAgentsDirectory.appendingPathComponent($0) }

    /// Each fixture file of the local layers and of the marketplace, relative
    /// to `Examples/agent-library`.
    private static let layerFiles = [
        "defaults/agents/code-reviewer.md",
        "defaults/agents/test-writer.md",
        "defaults/agents/lead.md",
        "defaults/_partials/house-rules.md",
        "defaults/skills/review/SKILL.md",
        "user/agents/code-reviewer.md",
        "project/.agents/agents/code-reviewer.md",
        "project/.agents/agents/internal-helper.md",
        "project/.agents/agents/release-manager.md",
        "marketplace/.claude-plugin/marketplace.json",
        "marketplace/plugins/code-tools/_partials/house-rules.md",
        "marketplace/plugins/code-tools/skills/review/SKILL.md",
        "marketplace/plugins/code-tools/agents/security-reviewer.md",
        "marketplace/plugins/docs-tools/agents/doc-writer.md"
    ]

    /// The path of the agent that each local layer holds a copy of.
    private static let sharedAgentPath = "agents/code-reviewer.md"

    /// The plugin names of the fixture marketplace catalog, in order.
    private static let marketplacePluginNames = ["code-tools", "docs-tools"]

    /// The roots of the three local layers, lowest layer first, in standard
    /// form.
    private static var localLayerRoots: [URL] {
        [
            FixtureLibrary.defaultsDirectory,
            FixtureLibrary.userDirectory,
            FixtureLibrary.projectDirectory
        ].map(\.standardizedFileURL)
    }

    @Test("each fixture file exists", arguments: expectedFiles)
    func fixtureFileExists(file: URL) {
        #expect(FileManager.default.fileExists(atPath: file.path), "Missing fixture: \(file.path)")
    }

    @Test("broken/agents holds exactly the broken fixtures")
    func brokenFolderHoldsTheBrokenFixtures() throws {
        let names = try FileManager.default.contentsOfDirectory(
            atPath: FixtureLibrary.brokenAgentsDirectory.path)
        #expect(Set(names) == Set(Self.brokenFileNames))
    }

    @Test("the stack has the defaults, user, and project layers in that order")
    func stackHasThreeLayersInOrder() {
        let layers = FixtureLibrary.stack().layers
        #expect(layers.map(\.source) == [.defaults, .user, .project])
        #expect(layers.map(\.root.standardizedFileURL.path) == Self.localLayerRoots.map(\.path))
    }

    @Test("the stack finds a copy of code-reviewer.md in each layer")
    func stackFindsEachLayer() {
        let copies = FixtureLibrary.stack().locate(Self.sharedAgentPath)
        let expected = Self.localLayerRoots.map { $0.appendingPathComponent(Self.sharedAgentPath).path }
        #expect(copies.map(\.standardizedFileURL.path) == expected)
    }

    @Test("the project copy of code-reviewer.md wins, and the view holds each local agent")
    func projectCopyWins() {
        let agents = FixtureLibrary.stack().enumerate("agents", suffix: ".md")
        #expect(Set(agents.keys) == FixtureLibrary.localAgentIDs)
        #expect(agents["code-reviewer"]?.layer.source == .project)
    }

    @Test("marketplace.json decodes as JSON and names the two plugins")
    func marketplaceCatalogDecodes() throws {
        let file = FixtureLibrary.marketplaceDirectory
            .appendingPathComponent(".claude-plugin", isDirectory: true)
            .appendingPathComponent("marketplace.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
        let catalog = try #require(object as? [String: Any])
        let plugins = try #require(catalog["plugins"] as? [[String: Any]])
        #expect(plugins.compactMap { $0["name"] as? String } == Self.marketplacePluginNames)
    }

    @Test("security-reviewer.md preloads the review skill and includes house-rules.md")
    func securityReviewerHasSkillsAndInclude() throws {
        let text = try Self.fixtureText("marketplace/plugins/code-tools/agents/security-reviewer.md")
        #expect(text.contains("\nskills: [review]\n"))
        #expect(text.contains("{% include \"house-rules.md\" %}"))
    }

    @Test("the defaults review skill takes $ARGUMENTS and names no agent")
    func defaultsReviewSkillNamesNoAgent() throws {
        let text = try Self.fixtureText("defaults/skills/review/SKILL.md")
        #expect(text.contains("\n$ARGUMENTS\n"))
        #expect(!text.contains("\nagent:"))
    }

    @Test("doc-writer.md names the model sonnet")
    func docWriterNamesSonnet() throws {
        let text = try Self.fixtureText("marketplace/plugins/docs-tools/agents/doc-writer.md")
        #expect(text.contains("\nmodel: sonnet\n"))
    }

    /// Reads the fixture at `relativePath` as UTF-8 text.
    ///
    /// - Parameter relativePath: A path relative to `Examples/agent-library`.
    /// - Returns: The whole text of the file.
    /// - Throws: An error when the file is not there, or is not UTF-8 text.
    private static func fixtureText(_ relativePath: String) throws -> String {
        try String(contentsOf: FixtureLibrary.url(relativePath), encoding: .utf8)
    }
}
