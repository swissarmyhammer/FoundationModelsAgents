import Foundation
import Testing

/// Holds `docs/skills-and-agents.md` to its rules (plan.md §14, M8).
///
/// The document must hold the table of plan.md §2, state that skills and
/// agents are separate things, and state how an agent uses a skill. Each
/// relative link of the document must resolve to a file or a folder of the
/// repository. The suite also tests the link reader on texts in memory, thus
/// a link to a missing file fails a case here.
@Suite("docs/skills-and-agents.md")
struct DocsTests {
    /// The folder of the documents, relative to the package root.
    private static let docsDirectory = "docs"

    /// The name of the document.
    private static let documentName = "skills-and-agents.md"

    /// The header row of the table of plan.md §2.
    private static let tableHeaderRow = "| Skills decision | Agents |"

    /// The key of a skill that makes the skill an agent. Skills and agents
    /// are separate things, thus the document does not describe this key.
    private static let agentSkillKey = "`agent:`"

    /// Every text that the document must hold.
    private static let claims = [
        "Skills and agents are separate things.",
        "uses skills through its `skills:` preload and through the `skills` tool",
        "To run a skill in its own context,",
        "a prompt tells an agent that has the `skills` tool to use the named skill.",
        "gives `skills/` and `agents/`",
        "`<plugin root>/_partials/`"
    ]

    /// A relative link to a file that the repository does not have.
    private static let missingLink = "no-such-file.md"

    /// A relative link from `docs/` to a file of the repository.
    private static let readmeLink = "../README.md"

    /// A relative link from `docs/` to a file of the repository, with a
    /// heading part.
    private static let planLinkWithHeading = "../plan.md#2-skills-and-agents"

    /// The file path of ``planLinkWithHeading``.
    private static let planLink = "../plan.md"

    /// A Markdown text with one link of each kind: missing, relative,
    /// relative with a heading, absolute, and to a heading of the same text.
    private static let linkSample = """
        See [a](\(missingLink)), [the README](\(readmeLink)), [the plan](\(planLinkWithHeading)),
        [the site](https://example.com/docs), and [the top](#top).
        """

    @Test func theDocumentHoldsTheSkillsTableHeaderRow() throws {
        let lines = try Self.readDocument().components(separatedBy: .newlines)

        #expect(lines.contains(Self.tableHeaderRow), "\(Self.documentName) must hold the table of plan.md §2")
    }

    @Test(arguments: claims)
    func theDocumentMakesTheClaim(claim: String) throws {
        let text = try Self.readDocument()

        #expect(text.contains(claim), "\(Self.documentName) must state \"\(claim)\"")
    }

    @Test func theDocumentDoesNotDescribeAnAgentKeyOfASkill() throws {
        let text = try Self.readDocument()

        #expect(!text.contains(Self.agentSkillKey), "skills and agents are separate things")
    }

    @Test(arguments: DocumentationTests.speedWords)
    func theDocumentGivesNoSpeedWord(word: String) throws {
        let lines = try Self.readDocument().lowercased().components(separatedBy: .newlines)

        #expect(
            !lines.contains { SwiftSourceScan.holds(token: word, in: $0) },
            "\(Self.documentName) must not say \"\(word)\"")
    }

    @Test func eachRelativeLinkOfTheDocumentResolves() throws {
        let text = try Self.readDocument()

        #expect(
            !MarkdownLinks.relativePaths(in: text).isEmpty,
            "the document holds a relative link, or the check proves nothing")
        #expect(MarkdownLinks.missingPaths(in: text, relativeTo: Self.docsURL).isEmpty)
    }

    @Test func theLinkReaderGivesTheRelativePathsWithNoHeadingPart() {
        let expected = [Self.missingLink, Self.readmeLink, Self.planLink]

        #expect(MarkdownLinks.relativePaths(in: Self.linkSample) == expected)
    }

    @Test func aLinkToAMissingFileIsReported() {
        #expect(MarkdownLinks.missingPaths(in: Self.linkSample, relativeTo: Self.docsURL) == [Self.missingLink])
    }

    /// The folder of the documents.
    private static var docsURL: URL {
        PackageRoot.directory.appendingPathComponent(docsDirectory, isDirectory: true)
    }

    /// Reads the document.
    ///
    /// - Returns: The text of the document.
    /// - Throws: An error when the document is not readable UTF-8 text.
    private static func readDocument() throws -> String {
        try String(contentsOf: docsURL.appendingPathComponent(documentName), encoding: .utf8)
    }
}
