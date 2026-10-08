import Foundation
import Testing

/// Holds the API documentation of this package to its rules (plan.md §14,
/// M8).
///
/// The first rule reads the Swift source: each public declaration and each
/// enum case has a doc comment (`DocCommentRule`). The suite walks each file
/// under `Sources/`, and it tests the rule itself on sources in memory. Thus a
/// public symbol that loses its doc comment fails a case here.
///
/// The other rules read the DocC catalog from the disk, with the method of
/// the `DocumentationTests` suite of FoundationModelsSkills: one row for each
/// claim that a page must make, and one row for each page and each wording
/// that no page may use. The catalog has the landing page and the four
/// articles, the landing page links each article, and the pages state the
/// design facts of the package in the words of the design.
@Suite("Documentation")
struct DocumentationTests {
    /// One text that one page of the DocC catalog must hold, or must not
    /// hold.
    struct Claim: Sendable, CustomTestStringConvertible {
        /// The name of the page, with no `.md` suffix.
        let page: String

        /// The text, in the spelling of the page.
        let text: String

        /// The name of the row in the test report.
        var testDescription: String {
            "\(page): \(text)"
        }
    }

    // MARK: - The source

    /// The directory of the library source, relative to the package root.
    private static let sourceDirectory = "Sources"

    /// A public type with a doc comment on each public symbol.
    private static let documentedSource = [
        "/// A run of one agent.",
        "public struct Example: Sendable {",
        "    /// The id of the run.",
        "    public let id: String",
        "",
        "    /// Makes a run.",
        "    @discardableResult",
        "    public init(id: String) {",
        "        self.id = id",
        "    }",
        "}"
    ]

    /// The index of the doc comment of `id` in `documentedSource`. With the
    /// doc comment removed, the declaration of `id` has this index.
    private static let idDocCommentIndex = 2

    /// The number of the first line of a source.
    private static let firstLineNumber = 1

    /// The count of reported lines in each source of
    /// `aSymbolWithNoDocCommentIsReported(source:)`.
    private static let oneReportedLine = 1

    // MARK: - The DocC catalog

    /// The DocC catalog of the library, relative to the package root.
    static let catalogPath = "Sources/FoundationModelsAgents/FoundationModelsAgents.docc"

    /// The suffix of a page of the catalog.
    static let pageSuffix = ".md"

    /// The landing page of the catalog.
    private static let landingPage = "FoundationModelsAgents"

    /// The article on the registry and its catalog.
    private static let catalogArticle = "LoadingTheCatalog"

    /// The article on a run.
    private static let runArticle = "RunningAnAgent"

    /// The article on the `agents` tool.
    private static let toolArticle = "DelegatingWithTheAgentsTool"

    /// The article on the final message.
    private static let finalMessageArticle = "TheFinalMessage"

    /// The four articles of the catalog.
    private static let articles = [catalogArticle, runArticle, toolArticle, finalMessageArticle]

    /// Each page of the catalog.
    static let pages = [landingPage] + articles

    /// The words that give speed as the reason of a design. The reason that
    /// the registry reads its files in `load()` is that the I/O shows at the
    /// call site, thus no page gives speed as a reason. `DocsTests` holds the
    /// documents under `docs/` to the same list.
    static let speedWords = ["slow", "slower", "fast", "faster", "speed", "cheap", "expensive"]

    /// The rule of the mount table that gives the full `agents` tool to a run
    /// (plan.md §5, §9.3). A page wraps its lines, thus each rule text fits
    /// on one line of the page.
    private static let agentsToolRule = "Only an explicit `tools` entry gives the operations that start agents."

    /// The rule of the mount table for an agent with no `tools` key
    /// (plan.md §5, §9.3): a run with a caller gets only the message
    /// operations, and a host-started run gets no `agents` tool.
    private static let noToolsKeyRule =
        "An agent with no `tools` key gets only the message operations, and only in a run with a caller."

    /// The rule of the noun synonym of `send caller` (plan.md §9.1).
    private static let parentSynonymRule = "`send parent` is the same call as `send caller`."

    /// The operations of the `agents` tool (plan.md §9.1), in tool order.
    private static let toolOperations = [
        "list agents", "start agent", "check agent", "cancel agent", "send agent", "send caller"
    ]

    /// The rule of the mount of `start agent` (plan.md §9.1).
    private static let backgroundRunRule = "`start agent` is a background run."

    /// The rule that gives the final message to the caller (plan.md §9.2).
    private static let mailRule = "The final message comes to the calling session as mail."

    /// The rule that delivers the mail (plan.md §9.2).
    private static let pumpRule = "The pump of the Router delivers the mail."

    /// The rule of the end of a run (plan.md §8 step 8).
    private static let idleRule = "A run ends when its session is idle."

    /// Every claim that a page must make.
    private static let claims: [Claim] =
        articles.map { Claim(page: landingPage, text: "<doc:\($0)>") }
        + toolOperations.map { Claim(page: toolArticle, text: "`\($0)`") }
        + [
            Claim(page: landingPage, text: "Skills and agents are separate things."),
            Claim(page: landingPage, text: "uses skills through its `skills:` preload and through the `skills` tool"),
            Claim(page: catalogArticle, text: "An init of ``AgentRegistry`` stores its inputs and reads no file."),
            Claim(page: catalogArticle, text: "``AgentRegistry/load()``"),
            Claim(page: catalogArticle, text: "``AgentRegistry/reload()``"),
            Claim(page: catalogArticle, text: "Both are `async throws`."),
            Claim(page: catalogArticle, text: "shows the I/O at the call site"),
            Claim(page: runArticle, text: "The run id is the session id"),
            Claim(page: runArticle, text: "The `maxTurns` key counts the passes of the control loop."),
            Claim(page: runArticle, text: "``AgentRunFailure/hitMaxTurns(partial:)``"),
            Claim(page: runArticle, text: noToolsKeyRule),
            Claim(page: runArticle, text: agentsToolRule),
            Claim(page: toolArticle, text: agentsToolRule),
            Claim(page: toolArticle, text: noToolsKeyRule),
            Claim(page: toolArticle, text: parentSynonymRule),
            Claim(page: toolArticle, text: "To run a skill in its own context"),
            Claim(page: finalMessageArticle, text: "`.completed` `OperationEvent`"),
            Claim(page: runArticle, text: idleRule),
            Claim(page: toolArticle, text: backgroundRunRule),
            Claim(page: toolArticle, text: mailRule),
            Claim(page: finalMessageArticle, text: backgroundRunRule),
            Claim(page: finalMessageArticle, text: mailRule),
            Claim(page: finalMessageArticle, text: pumpRule),
            Claim(page: finalMessageArticle, text: idleRule),
            Claim(page: finalMessageArticle, text: "``AgentRunner/cancelRuns(caller:)``")
        ]

    /// One row for each page and each speed word.
    private static let speedRows: [Claim] = pages.flatMap { page in
        speedWords.map { Claim(page: page, text: $0) }
    }

    // MARK: - The doc comment rule

    @Test func aSourceWithADocCommentOnEachPublicSymbolIsNotReported() {
        #expect(DocCommentRule.undocumentedLines(in: Self.documentedSource).isEmpty)
    }

    @Test func aPublicSymbolThatLosesItsDocCommentIsReported() {
        let source = Self.documentedSource.enumerated()
            .filter { $0.offset != Self.idDocCommentIndex }
            .map(\.element)
        let expectedLine = Self.idDocCommentIndex + Self.firstLineNumber

        #expect(DocCommentRule.undocumentedLines(in: source) == [expectedLine])
    }

    @Test(arguments: [
        ["public func start() {}"],
        ["/// Starts.", "", "public func start() {}"],
        ["// Starts.", "public func start() {}"],
        ["@MainActor", "public final class Runner {}"],
        ["    nonisolated public var names: [String] { [] }"],
        ["/// A state.", "public enum State {", "    case running", "}"],
        ["enum Phase {", "    case waitingForChildren(count: Int)", "}"]
    ])
    func aSymbolWithNoDocCommentIsReported(source: [String]) {
        #expect(DocCommentRule.undocumentedLines(in: source).count == Self.oneReportedLine)
    }

    @Test(arguments: [
        ["/// Starts.", "@discardableResult", "public func start() -> Int { 1 }"],
        [
            "/// Lists the agents.",
            "@Operation(",
            "    verb: \"list\", noun: \"agents\",",
            "    description: \"List each agent.\")",
            "public struct ListAgents {}"
        ],
        ["func start() {}"],
        ["    private static let limit = 4"],
        ["let text = \"public func start()\""],
        ["// public func start() {}"],
        ["switch state {", "case running:", "case .finished(let text):", "case let .failed(failure):", "}"]
    ])
    func aSymbolWithADocCommentOrNoPublicSymbolIsNotReported(source: [String]) {
        #expect(DocCommentRule.undocumentedLines(in: source).isEmpty)
    }

    @Test func eachPublicSymbolOfTheLibraryHasADocComment() throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.sourceDirectory, using: DocCommentRule.undocumentedLines)

        #expect(
            offenders.isEmpty,
            """
            Each public declaration and each enum case needs a doc comment directly above it; \
            found none at: \(offenders.joined(separator: ", "))
            """)
    }

    // MARK: - The DocC catalog

    @Test(arguments: pages)
    func theCatalogHasThePage(page: String) throws {
        let text = try Self.readPage(page)

        #expect(!text.isEmpty, "\(page)\(Self.pageSuffix) must not be empty")
    }

    @Test(arguments: claims)
    func theCatalogMakesEveryClaim(claim: Claim) throws {
        let text = try Self.readPage(claim.page)

        #expect(text.contains(claim.text), "\(claim.page)\(Self.pageSuffix) must state \"\(claim.text)\"")
    }

    @Test(arguments: speedRows)
    func noPageGivesSpeedAsTheReasonOfTheDesign(row: Claim) throws {
        let lines = try Self.readPage(row.page).lowercased().components(separatedBy: .newlines)

        #expect(
            !lines.contains { SwiftSourceScan.holds(token: row.text, in: $0) },
            """
            \(row.page)\(Self.pageSuffix) must not say "\(row.text)": the registry reads its files in \
            load() so that the I/O shows at the call site
            """)
    }

    // MARK: - The count of the operations

    @Test func noSourceOrDocumentStatesFourOperations() throws {
        let offenders = try Self.textFiles().filter { url in
            Self.holdsFourOperations(try String(contentsOf: url, encoding: .utf8))
        }

        #expect(
            offenders.isEmpty,
            """
            The `agents` tool has \(Self.toolOperations.count) operations, thus no file may say \
            "\(Self.fourOperationsText)": \(offenders.map(\.path).joined(separator: ", "))
            """)
    }

    @Test func aCountThatALineBreakSplitsIsFound() {
        #expect(Self.holdsFourOperations("with the name `agents` and Four\n   operations:"))
    }

    @Test func aTextWithNoCountIsNotReported() {
        #expect(!Self.holdsFourOperations("the four forms of the description, and six operations"))
    }

    /// The count of the operations that no file may state. The tool has the
    /// operations of ``toolOperations``.
    private static let fourOperationsText = "four operations"

    /// The folders of the files that the count check reads, relative to the
    /// package root: the source with the DocC catalog, and the documents.
    private static let textDirectories = [sourceDirectory, "docs"]

    /// The files at the package root that the count check reads.
    private static let rootTextFiles = ["README.md", "plan.md"]

    /// The extensions of the files that the count check reads.
    private static let textExtensions: Set = ["swift", "md"]

    /// Tells whether `text` states the count ``fourOperationsText``. A page
    /// can wrap the two words over two lines, thus the check reads each run
    /// of white space as one space. The case of the letters does not matter.
    ///
    /// - Parameter text: The text of one file.
    /// - Returns: `true` when the text holds the count.
    private static func holdsFourOperations(_ text: String) -> Bool {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .contains(fourOperationsText)
    }

    /// Gives each file that the count check reads: each Swift and Markdown
    /// file under ``textDirectories``, and ``rootTextFiles``.
    ///
    /// - Returns: The URLs of the files.
    /// - Throws: An error when a folder cannot be read.
    private static func textFiles() throws -> [URL] {
        let root = PackageRoot.directory
        let folderFiles = try textDirectories.flatMap { directory in
            let folder = root.appendingPathComponent(directory, isDirectory: true)
            let files = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
            return files.compactMap { $0 as? URL }.filter { textExtensions.contains($0.pathExtension) }
        }
        return folderFiles + rootTextFiles.map { root.appendingPathComponent($0) }
    }

    /// Reads one page of the DocC catalog.
    ///
    /// - Parameter page: The name of the page, with no `.md` suffix.
    /// - Returns: The text of the page.
    /// - Throws: An error when the page is not readable UTF-8 text.
    private static func readPage(_ page: String) throws -> String {
        let url = PackageRoot.directory
            .appendingPathComponent(catalogPath, isDirectory: true)
            .appendingPathComponent(page + pageSuffix)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
