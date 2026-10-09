import Foundation
import FoundationModelsExtras
import Testing

/// Pins the fixture library at `Examples/agent-library`.
///
/// The suite makes sure that each fixture file exists, that
/// `FixtureLibrary.stack()` gives the three local layers in order, that the
/// fixture marketplace holds no catalog file, and that the marketplace agents
/// hold the keys that later suites use.
@Suite("Fixture library")
struct FixtureLibraryTests {
    /// The agent folder names of the `broken/agents/` fixtures, each with one
    /// defect.
    private static let brokenFolderNames = [
        "bad-colon-description",
        "missing-description",
        "bad-name",
        "Bad_Name",
        "no-frontmatter",
        "unknown-model",
        "unknown-disallowed-tool"
    ]

    /// The agent file of the old format in `broken/agents/`. It gives a
    /// warning and no agent.
    private static let oldFormatFileName = "old-format.md"

    /// The URL of each fixture file: the layer files, the broken agent
    /// documents, then the old-format file.
    private static let expectedFiles = layerFiles.map(FixtureLibrary.url)
        + brokenFolderNames.map {
            FixtureLibrary.brokenAgentsDirectory.appendingPathComponent($0)
                .appendingPathComponent(AgentDocumentPath.documentName)
        }
        + [FixtureLibrary.brokenAgentsDirectory.appendingPathComponent(oldFormatFileName)]

    /// Each fixture file of the local layers and of the marketplace, relative
    /// to `Examples/agent-library`.
    private static let layerFiles = [
        "defaults/\(AgentDocumentPath.of("code-reviewer"))",
        "defaults/\(AgentDocumentPath.of("test-writer"))",
        "defaults/\(AgentDocumentPath.of("lead"))",
        "defaults/_partials/house-rules.md",
        "defaults/skills/review/SKILL.md",
        "user/\(AgentDocumentPath.of("code-reviewer"))",
        "project/.agents/\(AgentDocumentPath.of("code-reviewer"))",
        "project/.agents/\(AgentDocumentPath.of("internal-helper"))",
        "project/.agents/\(AgentDocumentPath.of("release-manager"))",
        "marketplace/plugins/code-tools/_partials/house-rules.md",
        "marketplace/plugins/code-tools/skills/review/SKILL.md",
        securityReviewerPath,
        "marketplace/plugins/code-tools/agents/security-reviewer/checklist.md",
        docWriterPath
    ]

    /// The document of the security-reviewer agent of the `code-tools`
    /// plugin.
    private static let securityReviewerPath =
        "marketplace/plugins/code-tools/\(AgentDocumentPath.of("security-reviewer"))"

    /// The document of the doc-writer agent of the `docs-tools` plugin.
    private static let docWriterPath = "marketplace/plugins/docs-tools/\(AgentDocumentPath.of("doc-writer"))"

    /// The path of the agent that each local layer holds a copy of.
    private static let sharedAgentPath = AgentDocumentPath.of("code-reviewer")

    /// The catalog file of a Claude marketplace. The fixture marketplace does
    /// not hold it: a scan of the folders finds each agent and each skill.
    private static let catalogFilePath = ".claude-plugin/marketplace.json"

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

    @Test("broken/agents holds exactly the broken agent folders and the old-format file")
    func brokenFolderHoldsTheBrokenFixtures() throws {
        let names = try FileManager.default.contentsOfDirectory(
            atPath: FixtureLibrary.brokenAgentsDirectory.path)
        #expect(Set(names) == Set(Self.brokenFolderNames + [Self.oldFormatFileName]))
    }

    @Test("the stack has the defaults, user, and project layers in that order")
    func stackHasThreeLayersInOrder() {
        let layers = FixtureLibrary.stack().layers
        #expect(layers.map(\.source) == [.defaults, .user, .project])
        #expect(layers.map(\.root.standardizedFileURL.path) == Self.localLayerRoots.map(\.path))
    }

    @Test("the stack finds a copy of agents/code-reviewer/AGENT.md in each layer")
    func stackFindsEachLayer() {
        let copies = FixtureLibrary.stack().locate(Self.sharedAgentPath)
        let expected = Self.localLayerRoots.map { $0.appendingPathComponent(Self.sharedAgentPath).path }
        #expect(copies.map(\.standardizedFileURL.path) == expected)
    }

    @Test("the project copy of code-reviewer wins, and the view holds each local agent")
    func projectCopyWins() {
        let agents = FixtureLibrary.stack().items(
            in: AgentDocumentPath.agentsFolderName, named: AgentDocumentPath.documentName)
        #expect(Set(agents.keys) == FixtureLibrary.localAgentIDs)
        #expect(agents["code-reviewer"]?.layer.source == .project)
    }

    @Test("the fixture marketplace holds no catalog file")
    func marketplaceHoldsNoCatalogFile() {
        let file = FixtureLibrary.marketplaceDirectory.appendingPathComponent(Self.catalogFilePath)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("security-reviewer preloads the review skill and includes house-rules.md")
    func securityReviewerHasSkillsAndInclude() throws {
        let text = try Self.fixtureText(Self.securityReviewerPath)
        #expect(text.contains("\nskills: [review]\n"))
        #expect(text.contains("{% include \"house-rules.md\" %}"))
    }

    @Test("the defaults review skill takes $ARGUMENTS and names no agent")
    func defaultsReviewSkillNamesNoAgent() throws {
        let text = try Self.fixtureText("defaults/skills/review/SKILL.md")
        #expect(text.contains("\n$ARGUMENTS\n"))
        #expect(!text.contains("\nagent:"))
    }

    @Test("doc-writer names the model sonnet")
    func docWriterNamesSonnet() throws {
        let text = try Self.fixtureText(Self.docWriterPath)
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
