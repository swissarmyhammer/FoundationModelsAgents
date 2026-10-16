import Foundation
import FoundationModels
import FoundationModelsSkills
import Testing

@testable import FoundationModelsAgents

/// Pins `find agents` and the search under it (D61).
///
/// The search ranks the descriptions of the model-visible agents with the
/// retrieval tier of `MetadataSearcher` (keywords and the embedding), and a
/// selection model picks among them, as the `skills` tool does. Each row uses
/// the fixture catalog or a temporary layer, the scripted embedding of the
/// test profile, and a scripted selection model. No row uses a real model.
@Suite("find agents")
struct FindAgentsTests {
    // MARK: - Constants

    /// The op string of the operation.
    private static let findOp = "find agents"

    /// A query in the words of the description of the test writer.
    private static let testQuery = "write unit tests"

    /// The id of the agent that ``testQuery`` describes.
    private static let testWriterName = "test-writer"

    /// The line of the test writer in an answer.
    private static let testWriterLine = "- test-writer: Writes unit tests for the code that the prompt names."

    /// The id of the project copy of the code reviewer.
    private static let reviewerName = "code-reviewer"

    /// The line of the project copy of the code reviewer in an answer.
    private static let reviewerLine =
        "- code-reviewer: Reviews code for quality and best practices. This is the project copy."

    /// The selection that picks only the code reviewer.
    private static let reviewerSelection = #"{"ids": ["code-reviewer"]}"#

    /// The fixture agent with `disable-model-invocation: true`.
    private static let hiddenName = "release-manager"

    /// A query in the words of the description of ``hiddenName``.
    private static let hiddenQuery = "prepare the release notes for a version"

    /// The model-visible agents of the fixture library.
    private static let visibleNames: Set = ["code-reviewer", "internal-helper", "lead", "test-writer"]

    /// A search limit above the count of the agents of the fixture library.
    private static let searchLimit = 10

    /// The start of each agent line: a dash and a space.
    private static let linePrefix = "- "

    /// The text between two lines of an answer.
    private static let lineBreak = "\n"

    /// The id of the agent that a reload adds.
    private static let laterName = "later-agent"

    /// The description of ``laterName``.
    private static let laterDescription = "Translates the documents into French."

    /// A query in the words of ``laterDescription``.
    private static let laterQuery = "translate the documents"

    /// The id of the agent of the first catalog of the reload row.
    private static let firstName = "first-agent"

    // MARK: - The operation

    @Test("the agent whose description matches the query comes first")
    func theMatchingAgentComesFirst() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await harness.call(Self.findOp, ["query": Self.testQuery])

        #expect(answer.components(separatedBy: Self.lineBreak).first == Self.testWriterLine)
        #expect(answer.hasSuffix(AgentsToolDescription.delegationSentence))
    }

    @Test("an agent that the model cannot see is not found")
    func aHiddenAgentIsNotFound() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await harness.call(Self.findOp, ["query": Self.hiddenQuery])

        #expect(!answer.contains(Self.hiddenName))
    }

    @Test("the limit caps the count of the agents")
    func theLimitCapsTheCount() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await Self.find(Self.testQuery, limit: 1, with: harness.tool)
        let agentLines = answer.components(separatedBy: Self.lineBreak).filter { $0.hasPrefix(Self.linePrefix) }

        #expect(agentLines == [Self.testWriterLine])
    }

    @Test("a limit below one gives a corrective")
    func aLimitBelowOneGivesACorrective() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await Self.find(Self.testQuery, limit: 0, with: harness.tool)

        #expect(answer == AgentsToolText.limitBelowOne)
    }

    @Test("a blank query gives a corrective")
    func aBlankQueryGivesACorrective() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        #expect(try await harness.call(Self.findOp, ["query": "  "]) == AgentsToolText.blankQuery)
    }

    @Test("a tool that can start no agent gives the no-agents answer")
    func noStartableAgentGivesTheNoAgentsAnswer() async throws {
        let (harness, layer) = try await AgentsToolHarness.makeEmpty()
        defer {
            try? harness.delete()
            try? layer.delete()
        }

        #expect(try await harness.call(Self.findOp, ["query": Self.testQuery]) == AgentsToolText.noAgents)
    }

    @Test("the skills selection model picks the agents of find agents")
    func theSkillsSelectionModelPicksTheAgents() async throws {
        let calls = SelectionProbeCalls()
        let registry = AgentRegistry(stack: FixtureLibrary.stack())
        try await registry.load()
        let environment = try await AgentEnvironment.make(
            profile: try await AgentEnvironmentTests.makeProfile(), skills: SkillsRegistry(roots: []),
            skillsSelectionModel: SelectionProbeModel(calls: calls, answer: Self.reviewerSelection))
        let tool = try await AgentsTool.make(
            context: AgentsToolContext(runner: AgentRunner(registry: registry, environment: environment)))

        let answer = try await Self.find(Self.testQuery, with: tool)

        #expect(answer.components(separatedBy: Self.lineBreak).first == Self.reviewerLine)
        #expect(!answer.contains(Self.testWriterLine))
        #expect(calls.count > 0)
    }

    // MARK: - The search

    @Test("the search index holds each model-visible agent and no other")
    func theIndexHoldsOnlyModelVisibleAgents() async throws {
        let registry = AgentRegistry(stack: FixtureLibrary.stack())
        try await registry.load()
        let search = AgentSearch(registry: registry, selectionModel: nil, embedder: ScriptedEmbeddingContainer())

        let found = try await search.search(query: Self.hiddenQuery, limit: Self.searchLimit)

        #expect(!found.contains(Self.hiddenName))
        #expect(Set(found) == Self.visibleNames, "the constant embedding ranks each indexed agent")
    }

    @Test("the selection model picks among the agents")
    func theSelectionModelPicks() async throws {
        let calls = SelectionProbeCalls()
        let search = try await Self.fixtureSearch(
            selectionModel: SelectionProbeModel(calls: calls, answer: Self.reviewerSelection))

        let found = try await search.search(query: Self.testQuery, limit: Self.searchLimit)

        #expect(found == [Self.reviewerName])
        #expect(calls.count > 0)
    }

    @Test("a selection model that gives no answer gives the retrieval rank")
    func aFailedSelectionGivesTheRetrievalRank() async throws {
        let calls = SelectionProbeCalls()
        let search = try await Self.fixtureSearch(selectionModel: SelectionProbeModel(calls: calls))

        let found = try await search.search(query: Self.testQuery, limit: Self.searchLimit)

        #expect(found.first == Self.testWriterName)
        #expect(calls.count > 0)
    }

    @Test("the search index follows each catalog of onReload")
    func theIndexFollowsEachReload() async throws {
        let layer = try TemporaryLayer.make(holding: [
            AgentDocumentPath.of(Self.firstName): AgentFolderFixture.agentText(name: Self.firstName)
        ])
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer])
        try await registry.load()
        let embedder = SignalingEmbedder()
        let search = AgentSearch(registry: registry, selectionModel: nil, embedder: embedder)

        try layer.write(
            AgentFolderFixture.agentText(name: Self.laterName, description: Self.laterDescription),
            at: AgentDocumentPath.of(Self.laterName))
        try await registry.reload()
        for await batch in embedder.batches where batch.contains(where: { $0.contains(Self.laterName) }) {
            break
        }

        #expect(try await search.search(query: Self.laterQuery, limit: Self.searchLimit).first == Self.laterName)
    }

    // MARK: - Support

    /// Makes a search over the loaded fixture library, with the scripted
    /// embedding.
    ///
    /// - Parameter selectionModel: The selection model of the search.
    /// - Returns: The search.
    /// - Throws: The error of `AgentRegistry.load()`.
    private static func fixtureSearch(selectionModel: any LanguageModel) async throws -> AgentSearch {
        let registry = AgentRegistry(stack: FixtureLibrary.stack())
        try await registry.load()
        return AgentSearch(registry: registry, selectionModel: selectionModel, embedder: ScriptedEmbeddingContainer())
    }

    /// Calls `find agents` on `tool`, as a model does.
    ///
    /// - Parameters:
    ///   - query: The query of the call.
    ///   - limit: The limit of the call, or `nil` for a call with no limit.
    ///   - tool: The `agents` tool.
    /// - Returns: The answer of the tool.
    /// - Throws: The error of `AgentsTool.call(arguments:)`.
    private static func find(_ query: String, limit: Int? = nil, with tool: AgentsTool) async throws -> String {
        guard let limit else {
            return try await tool.call(arguments: GeneratedContent(properties: ["op": findOp, "query": query]))
        }
        return try await tool.call(
            arguments: GeneratedContent(properties: ["op": findOp, "query": query, "limit": limit]))
    }
}
