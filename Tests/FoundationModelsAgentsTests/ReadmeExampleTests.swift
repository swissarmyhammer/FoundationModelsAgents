import Foundation
import MarketplaceFixtures
import Testing

@testable import FoundationModelsAgents

/// The contract of the Swift examples of `README.md`.
///
/// Each Swift block of the README must have a compiled copy in
/// `ReadmeExampleSource.swift`, between the two marker comments of
/// ``ReadmeExample``. The run case runs the copy of the example with a
/// scripted profile over the fixture library and a git repository of the
/// fixture marketplace. Thus each README example compiles, runs, and gives a
/// result.
@Suite("README example")
struct ReadmeExampleTests {
    /// The instructions of the root session in the README example.
    private static let rootInstructions = "You give work to agents with the agents tool."

    /// A line of the body of the `review` skill of the `defaults` skill
    /// layer. The instructions of the security-reviewer run hold it only when
    /// the `skills:` preload worked.
    private static let preloadedSkillLine = "Review this code and give specific feedback:"

    /// The agent that the root session starts.
    private static let childAgent = "code-reviewer"

    /// The prompt that the root session gives to the child run.
    private static let childKey = "readme-child-key: review the parser"

    /// The final text of the host-driven security-reviewer run.
    private static let reviewText = "The parser checks each input."

    /// The final text of the child run.
    private static let childText = "The parser is correct."

    /// The answer of the first turn of the root session.
    private static let rootText = "I started code-reviewer."

    /// The agents of the catalog that the example uses: one of the
    /// marketplace and one of the local layers.
    private static let usedAgents: Set = ["security-reviewer", "code-reviewer"]

    /// The text that the change cases add to a line of a README block.
    private static let changedLineSuffix = " // changed"

    /// An import line that the example source does not have.
    private static let unknownImport = "import NoSuchModule"

    @Test("the README example runs with the scripted profile and gives a result", .timeLimit(.minutes(1)))
    func readmeExampleRunsWithTheScriptedProfile() async throws {
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: Self.rootInstructions,
                steps: [
                    NestedRunTests.startStep(Self.childAgent, prompt: Self.childKey),
                    .finalText(Self.rootText),
                    .finalTextOfLaterPrompts
                ]),
            ScriptedAgentPlay(key: Self.preloadedSkillLine, steps: [.finalText(Self.reviewText)]),
            ScriptedAgentPlay(key: Self.childKey, steps: [.finalText(Self.childText)])
        ])
        let recordings = try TemporaryLayer.makeEmpty()
        defer { try? recordings.delete() }
        let cache = try TemporaryLayer.makeEmpty()
        defer { try? cache.delete() }
        let repository = try GitFixtureRepository()
        _ = try repository.commit(files: FixtureMarketplaceProvider.fixtureTree())
        let (router, profile) = try await ScriptedProfile.make(script: script, recordingsDir: recordings.root)

        let outcome = try await ReadmeExampleSource.run(
            profile: profile,
            folders: ReadmeExampleSource.Folders(
                projectDirectory: FixtureLibrary.projectWorkingDirectory,
                shippedAgentsURL: FixtureLibrary.defaultsDirectory,
                shippedSkillsURL: FixtureLibrary.url("defaults/skills"),
                userConfigURL: FixtureLibrary.userDirectory,
                marketplaceURL: repository.url,
                cacheDirectory: cache.root))
        withExtendedLifetime((router, repository)) {}

        #expect(Set(outcome.listing.map(\.id)).isSuperset(of: Self.usedAgents))
        #expect(outcome.review == Self.reviewText)
        #expect(try #require(outcome.answer).contains(try Self.finishedChildDetail()))
    }

    @Test("each Swift block of the README has a compiled copy in the example source")
    func eachReadmeBlockHasACompiledCopy() throws {
        let blocks = try Self.readmeBlocks()
        let source = try Self.exampleSource()

        #expect(!blocks.isEmpty, "the README holds at least one Swift block, or the check proves nothing")
        for block in blocks {
            #expect(ReadmeExample.hasCopy(of: block, in: source), "no compiled copy of: \(block)")
        }
    }

    @Test("each compiled copy of the example source is a Swift block of the README")
    func eachCompiledCopyIsAReadmeBlock() throws {
        let blockCode = try Self.readmeBlocks().map(ReadmeExample.code(of:))
        let copies = ReadmeExample.copies(in: try Self.exampleSource())

        #expect(!copies.isEmpty, "the example source holds at least one copy, or the check proves nothing")
        for copy in copies {
            #expect(blockCode.contains(copy), "no README block for the copy: \(copy)")
        }
    }

    @Test("a README block with a changed line has no compiled copy")
    func aChangedReadmeLineHasNoCompiledCopy() throws {
        let block = try #require(try Self.readmeBlocks().first)
        let lastLine = try #require(block.last)
        let changed = Array(block.dropLast()) + [lastLine + Self.changedLineSuffix]

        #expect(!ReadmeExample.hasCopy(of: changed, in: try Self.exampleSource()))
    }

    @Test("a README block with an import that the source does not have has no compiled copy")
    func anUnknownReadmeImportHasNoCompiledCopy() throws {
        let block = try #require(try Self.readmeBlocks().first)

        #expect(!ReadmeExample.hasCopy(of: [Self.unknownImport] + block, in: try Self.exampleSource()))
    }

    /// Gives the pattern of the final message of the finished child run:
    /// "Agent code-reviewer (`id`) finished.", a blank line, and its text.
    /// The example does not give the id of the child, thus the pattern
    /// accepts each id.
    ///
    /// - Returns: The pattern.
    /// - Throws: The error of the pattern compile.
    private static func finishedChildDetail() throws -> Regex<AnyRegexOutput> {
        let text = NSRegularExpression.escapedPattern(for: childText)
        return try Regex("Agent \(childAgent) \\(\\w+\\) finished\\.\n\n\(text)")
    }

    /// Reads the Swift blocks of `README.md`.
    ///
    /// - Returns: The trimmed lines of each Swift block, in text order.
    /// - Throws: The error of the file read.
    private static func readmeBlocks() throws -> [[String]] {
        ReadmeExample.swiftBlocks(in: try String(contentsOf: ReadmeExample.readmeURL, encoding: .utf8))
    }

    /// Reads the text of `ReadmeExampleSource.swift`.
    ///
    /// - Returns: The text of the file.
    /// - Throws: The error of the file read.
    private static func exampleSource() throws -> String {
        try String(contentsOf: ReadmeExample.sourceURL, encoding: .utf8)
    }
}
