import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins `AgentFrontmatter.decode(_:)` (plan.md §4.2, §4.3 step 1).
///
/// The suite decodes the fixture frontmatter through a
/// `FrontmatterDocumentStack`, thus it also proves that the decode has the
/// signature that the stack wants.
@Suite("Agent frontmatter")
struct AgentFrontmatterTests {
    /// The path of an agent file, relative to a layer root.
    private static func agentPath(_ id: String) -> String {
        "agents/\(id).md"
    }

    /// The note that a decode records after the colon retry.
    private static let colonRetryNote = AgentFrontmatter.colonRetryNote

    /// The `maxTurns` value that the typed-field test writes.
    private static let turnLimit = 12

    /// A document stack over one layer at `root`, with the agent decode.
    ///
    /// - Parameter root: The root of the one layer.
    /// - Returns: The document stack.
    private static func documents(
        at root: URL
    ) -> FrontmatterDocumentStack<DotfolderStack, AgentFrontmatter> {
        let plain = DotfolderStack(layers: [DotfolderStack.Layer(source: .project, root: root)])
        return FrontmatterDocumentStack(base: plain, decode: AgentFrontmatter.decode)
    }

    @Test("the defaults code-reviewer frontmatter decodes to its values")
    func codeReviewerFixtureDecodes() throws {
        let documents = Self.documents(at: FixtureLibrary.defaultsDirectory)
        let located = try #require(documents.item(at: Self.agentPath("code-reviewer")))
        let frontmatter = try #require(located.value.metadata)

        #expect(
            frontmatter
                == AgentFrontmatter(
                    name: "code-reviewer",
                    description: "Reviews code for quality and best practices.",
                    tools: ["Read", "Grep"],
                    model: "flash"))
    }

    @Test("bad-colon-description decodes after the retry with one note")
    func badColonDescriptionDecodesAfterRetry() throws {
        let brokenRoot = FixtureLibrary.brokenAgentsDirectory.deletingLastPathComponent()
        let documents = Self.documents(at: brokenRoot)
        let located = try #require(documents.item(at: Self.agentPath("bad-colon-description")))
        let frontmatter = try #require(located.value.metadata)

        #expect(frontmatter.name == "bad-colon-description")
        #expect(frontmatter.description == "Deploy to staging: run the smoke tests first, then promote.")
        #expect(frontmatter.notes == [Self.colonRetryNote])
    }

    @Test("the retry escapes quotes and keeps a carriage return")
    func retryEscapesQuotesAndKeepsCarriageReturn() throws {
        let yaml = "name: quoted\r\ndescription: Say \"hi\": then \\ go\r\n"
        let frontmatter = try #require(AgentFrontmatter.decode(yaml))

        #expect(frontmatter.name == "quoted")
        #expect(frontmatter.description == "Say \"hi\": then \\ go")
        #expect(frontmatter.notes == [Self.colonRetryNote])
    }

    @Test(
        "invalid YAML after the retry gives nil",
        arguments: [
            "name: x\ntools: [Read",
            "description: a: b\ntools: [Read",
            "description: 'quoted': b'\n",
            "description:\n  nested: a: b\n",
            "- a list\n- at the top\n",
            "just a scalar\n"
        ])
    func invalidYAMLGivesNil(yaml: String) {
        #expect(AgentFrontmatter.decode(yaml) == nil)
    }

    @Test("empty frontmatter decodes to no fields")
    func emptyFrontmatterDecodesToNoFields() {
        #expect(AgentFrontmatter.decode("") == AgentFrontmatter())
        #expect(AgentFrontmatter.decode("# only a comment\n") == AgentFrontmatter())
    }

    @Test("a comma-separated text and a YAML list give the same list")
    func textAndListGiveTheSameList() throws {
        let text = try #require(AgentFrontmatter.decode("tools: Read, Grep\n"))
        let flowList = try #require(AgentFrontmatter.decode("tools: [Read, Grep]\n"))
        let blockList = try #require(AgentFrontmatter.decode("tools:\n  - Read\n  - Grep\n"))

        #expect(text.tools == ["Read", "Grep"])
        #expect(flowList.tools == text.tools)
        #expect(blockList.tools == text.tools)
    }

    @Test("Agent(a, b) stays one entry")
    func parenthesizedEntryStaysOne() throws {
        let yaml = """
            tools: Read, Agent(code-reviewer, test-writer), Grep
            disallowedTools:
              - Agent(lead, test-writer)
            skills: review,, docs ,
            """
        let frontmatter = try #require(AgentFrontmatter.decode(yaml))

        #expect(frontmatter.tools == ["Read", "Agent(code-reviewer, test-writer)", "Grep"])
        #expect(frontmatter.disallowedTools == ["Agent(lead, test-writer)"])
        #expect(frontmatter.skills == ["review", "docs"])
    }

    @Test("the typed tier 1 and tier 2 fields decode")
    func typedFieldsDecode() throws {
        let yaml = """
            maxTurns: \(Self.turnLimit)
            compactionPrompt: Keep the file names.
            disable-model-invocation: true
            user-invocable: false
            color: blue
            background: false
            """
        let frontmatter = try #require(AgentFrontmatter.decode(yaml))

        #expect(frontmatter.maxTurns == Self.turnLimit)
        #expect(frontmatter.compactionPrompt == "Keep the file names.")
        #expect(frontmatter.disableModelInvocation == true)
        #expect(frontmatter.userInvocable == false)
        #expect(frontmatter.color == "blue")
        #expect(frontmatter.background == false)
        #expect(frontmatter.notes.isEmpty)
    }

    @Test("a value of the wrong type is left out with a note")
    func wrongTypeGivesNote() throws {
        let yaml = """
            name: [not, text]
            maxTurns: many
            user-invocable: "false"
            tools: {Read: yes}
            skills: [review, [nested]]
            """
        let frontmatter = try #require(AgentFrontmatter.decode(yaml))

        #expect(frontmatter.name == nil)
        #expect(frontmatter.maxTurns == nil)
        #expect(frontmatter.userInvocable == nil)
        #expect(frontmatter.tools == nil)
        #expect(frontmatter.skills == ["review"])
        #expect(
            frontmatter.notes == [
                AgentFrontmatter.wrongTypeNote(key: "maxTurns", expected: .wholeNumber),
                AgentFrontmatter.wrongTypeNote(key: "name", expected: .text),
                AgentFrontmatter.wrongTypeNote(key: "skills", expected: .list),
                AgentFrontmatter.wrongTypeNote(key: "tools", expected: .list),
                AgentFrontmatter.wrongTypeNote(key: "user-invocable", expected: .flag)
            ])
    }

    @Test("a null value is absent with no note")
    func nullValueIsAbsent() throws {
        let frontmatter = try #require(AgentFrontmatter.decode("tools:\nmodel: ~\n"))

        #expect(frontmatter == AgentFrontmatter())
    }

    @Test("unknown keys and tier 3 keys are kept")
    func unknownAndUnsupportedKeysAreKept() throws {
        let yaml = """
            name: keeper
            permissionMode: plan
            hooks: {}
            memory: user
            x-team: core
            ratings: [1, 2]
            """
        let frontmatter = try #require(AgentFrontmatter.decode(yaml))

        #expect(frontmatter.name == "keeper")
        #expect(
            frontmatter.unsupportedFields == [
                "permissionMode": .string("plan"),
                "hooks": .dictionary([:]),
                "memory": .string("user")
            ])
        #expect(
            frontmatter.unknownFields == [
                "x-team": .string("core"),
                "ratings": .array([.int(1), .int(2)])
            ])
        #expect(frontmatter.notes.isEmpty)
    }

    @Test("each tier 3 key of plan.md §4.2 is unsupported")
    func tierThreeKeysAreUnsupported() {
        #expect(
            Set(AgentFrontmatter.unsupportedKeys)
                == [
                    "permissionMode", "mcpServers", "hooks", "memory", "effort", "isolation",
                    "initialPrompt"
                ])
    }

    @Test("a template in a value stays text")
    func templateStaysText() throws {
        let yaml = """
            description: Use {{ x }} here.
            compactionPrompt: Keep {% if a %}b{% endif %}.
            """
        let frontmatter = try #require(AgentFrontmatter.decode(yaml))

        #expect(frontmatter.description == "Use {{ x }} here.")
        #expect(frontmatter.compactionPrompt == "Keep {% if a %}b{% endif %}.")
    }
}
