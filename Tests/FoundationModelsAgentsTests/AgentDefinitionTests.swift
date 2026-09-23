import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Marketplace
import Testing

/// Pins the rule table of plan.md §4.3 step 2, and the visibility of
/// plan.md §4.2, on `AgentDefinition.init`.
///
/// The `broken/` rows load the fixture files. The inline rows build one
/// document from a frontmatter text. `AgentDefinitionRows` holds the rows.
@Suite("Agent definition")
struct AgentDefinitionTests {
    /// The type that makes each attempt.
    typealias Attempt = AgentDefinitionAttempt

    /// The type that holds the rows.
    typealias Rows = AgentDefinitionRows

    @Test("a broken fixture gives the severity of its rule", arguments: Rows.broken)
    func brokenFixtureGivesItsSeverity(row: Rows.BrokenRow) {
        let attempt = Attempt.broken(row.id)

        #expect(attempt.severities == row.severities)
        #expect((attempt.definition != nil) == row.loads)
        #expect(attempt.diagnostics.allSatisfy { $0.provenance.url.lastPathComponent == "\(row.id).md" })
    }

    @Test("bad-name loads with the file name as the id")
    func badNameKeepsTheFileNameAsTheID() throws {
        let attempt = Attempt.broken("bad-name")
        let definition = try #require(attempt.definition)

        #expect(definition.id == "bad-name")
        #expect(attempt.diagnostics.map(\.agent) == ["bad-name"])
        #expect(attempt.diagnostics.first?.message.contains("other-name") == true)
    }

    @Test("missing-description loads and is not model-visible")
    func missingDescriptionIsNotModelVisible() throws {
        let definition = try #require(Attempt.broken("missing-description").definition)

        #expect(definition.description == nil)
        #expect(!definition.isModelVisible)
        #expect(definition.isUserInvocable)
    }

    @Test("bad-colon-description loads with the colon retry note as an advisory")
    func badColonDescriptionGivesTheRetryNote() throws {
        let attempt = Attempt.broken("bad-colon-description")
        let definition = try #require(attempt.definition)

        #expect(definition.description == "Deploy to staging: run the smoke tests first, then promote.")
        #expect(attempt.diagnostics.map(\.message) == [AgentFrontmatter.colonRetryNote])
    }

    @Test("an inline frontmatter gives the severity of its rule", arguments: Rows.inline)
    func inlineFrontmatterGivesItsSeverity(row: Rows.InlineRow) throws {
        let attempt = Attempt.inline(row.yaml)

        #expect(attempt.severities == row.severities)
        #expect(attempt.diagnostics.allSatisfy { $0.agent == Attempt.inlineID })
        #expect(attempt.diagnostics.allSatisfy { $0.provenance == Attempt.inlineProvenance })
        #expect(try #require(attempt.definition).id == Attempt.inlineID)
    }

    @Test("the name rule accepts only 1 to 64 of [a-z0-9-] with no bad hyphen", arguments: Rows.ids)
    func nameRuleChecksTheFileName(row: Rows.IDRow) {
        let attempt = Attempt.inline(Attempt.validDescription, id: row.id)

        #expect((attempt.definition != nil) == row.isValid)
        #expect(attempt.severities.contains(.skip) == !row.isValid)
    }

    @Test("a skip for a bad file name gives no agent name")
    func badFileNameSkipHasNoAgent() {
        let attempt = Attempt.inline(Attempt.validDescription, id: "Bad_Name")

        #expect(attempt.severities == [.skip])
        #expect(attempt.diagnostics.map(\.agent) == [nil])
    }

    @Test("a missing document is a skip")
    func missingDocumentIsASkip() {
        let attempt = Attempt.make(id: Attempt.inlineID, document: nil, provenance: Attempt.inlineProvenance)

        #expect(attempt.definition == nil)
        #expect(attempt.severities == [.skip])
        #expect(attempt.diagnostics.map(\.agent) == [Attempt.inlineID])
    }

    @Test("a frontmatter that does not decode is a skip")
    func undecodedFrontmatterIsASkip() {
        let attempt = Attempt.inline("name: [unclosed")

        #expect(attempt.definition == nil)
        #expect(attempt.severities == [.skip])
    }

    @Test("the visibility follows the description and the two invocation keys", arguments: Rows.visibility)
    func visibilityFollowsTheKeys(row: Rows.VisibilityRow) throws {
        let definition = try #require(Attempt.inline(row.yaml).definition)

        #expect(definition.isModelVisible == row.isModelVisible)
        #expect(definition.isUserInvocable == row.isUserInvocable)
    }

    @Test("a long description stays model-visible")
    func longDescriptionStaysModelVisible() throws {
        let definition = try #require(Attempt.inline("description: \(Rows.longDescription)").definition)

        #expect(definition.isModelVisible)
        #expect(definition.description == Rows.longDescription)
    }

    @Test("a Claude file with permissionMode, hooks, and model: sonnet loads with advisories")
    func claudeFileLoadsWithAdvisories() throws {
        let yaml = """
            \(Rows.cleanLines)
            permissionMode: acceptEdits
            hooks:
              PreToolUse:
                - matcher: Bash
            model: sonnet
            """
        let attempt = Attempt.inline(yaml)
        let definition = try #require(attempt.definition)
        let messages = attempt.diagnostics.map(\.message)

        #expect(attempt.severities == [.advisory, .advisory])
        #expect(messages.first?.contains("'hooks'") == true)
        #expect(messages.last?.contains("'permissionMode'") == true)
        #expect(definition.model == "sonnet")
    }

    @Test("an empty model gives no model")
    func emptyModelGivesNoModel() throws {
        let definition = try #require(Attempt.inline("\(Attempt.validDescription)\nmodel: \" \"").definition)

        #expect(definition.model == nil)
    }

    @Test("the definition keeps each field of the frontmatter")
    func definitionKeepsEachField() throws {
        let maxTurns = 7
        let yaml = """
            \(Rows.cleanLines)
            tools: Read, Grep
            disallowedTools: Bash
            skills: [review]
            model: flash
            maxTurns: \(maxTurns)
            compactionPrompt: Keep each file path.
            color: blue
            background: true
            owner: docs-team
            """
        let definition = try #require(Attempt.inline(yaml).definition)

        #expect(definition.description == "An inline agent.")
        #expect(definition.body == Attempt.inlineBody)
        #expect(definition.tools == ["Read", "Grep"])
        #expect(definition.disallowedTools == ["Bash"])
        #expect(definition.skills == ["review"])
        #expect(definition.model == "flash")
        #expect(definition.maxTurns == maxTurns)
        #expect(definition.compactionPrompt?.text == "Keep each file path.")
        #expect(definition.compactionPrompt?.name != CompactionPrompt.default.name)
        #expect(definition.color == "blue")
        #expect(definition.background == true)
        #expect(definition.unknownFields == ["owner": .string("docs-team")])
    }

    @Test("absent list keys give nil tools and empty lists")
    func absentListKeysGiveDefaults() throws {
        let definition = try #require(Attempt.inline(Attempt.validDescription).definition)

        #expect(definition.tools == nil)
        #expect(definition.disallowedTools.isEmpty)
        #expect(definition.skills.isEmpty)
        #expect(definition.compactionPrompt == nil)
        #expect(definition.maxTurns == nil)
    }

    @Test("the definition keeps its provenance")
    func definitionKeepsItsProvenance() throws {
        let marketplace = MarketplaceProvenance(id: "acme", url: "https://example.com/acme.git", sha: "abc1234")
        let provenance = AgentDiagnostic.Provenance(
            layerIndex: 0, layerRoot: Attempt.inlineLayer.root, url: Attempt.inlineURL, marketplace: marketplace)
        let definition = try #require(
            Attempt.inline(Attempt.validDescription, provenance: provenance).definition)

        #expect(definition.url == Attempt.inlineURL)
        #expect(definition.layer.source == .project)
        #expect(definition.layer.root == Attempt.inlineLayer.root)
        #expect(definition.marketplace == marketplace)
        #expect(definition.provenance == provenance)
    }

    @Test("the listing carries the data of the definition")
    func listingCarriesTheDefinitionData() throws {
        let yaml = """
            \(Attempt.validDescription)
            model: flash
            color: green
            background: false
            owner: docs-team
            user-invocable: false
            """
        let listing = try #require(Attempt.inline(yaml).definition).listing

        #expect(listing.id == Attempt.inlineID)
        #expect(listing.description == "An inline agent.")
        #expect(listing.model == "flash")
        #expect(listing.color == "green")
        #expect(listing.background == false)
        #expect(listing.unknownFields == ["owner": .string("docs-team")])
        #expect(listing.isModelVisible)
        #expect(!listing.isUserInvocable)
        #expect(listing.provenance == Attempt.inlineProvenance)
    }
}
