import Testing

@testable import FoundationModelsAgents

/// Pins the description of the `agents` tool (plan.md §9.1).
///
/// The description has the fixed sentences, which are never cut, then the
/// model-visible agents in the first form that fits the character limit:
/// full lines, descriptions cut to 200 characters, names only, and as many
/// names as fit with a count of the other names. An empty catalog gives one
/// line.
@Suite("Agents tool description")
struct AgentsToolDescriptionTests {
    // MARK: - Constants

    /// The fixed sentences, word for word from plan.md §9.1.
    private static let fixedSentences =
        "An agent is a model session that works in the background. Each agent starts with an empty context "
        + "and sees only the prompt that you give it, so put all that the agent needs in the prompt. "
        + #"To give a task to an agent, call this tool with {"op": "start agent", "name": "<name>", "#
        + #""prompt": "<the full task>"}. The call returns at once. When the agent finishes, its final "#
        + "message comes to you as a tool result. Your answer is the text of your last turn, so give your "
        + "final answer after you have the results of the agents that you started. You can ask about a run "
        + #"with {"op": "check agent", "id": "<id>"}."#

    /// The text between the fixed sentences and the agent list.
    private static let listSeparator = "\n\n"

    /// The line of an empty catalog.
    private static let noAgentsLine = "No agents are installed now."

    /// The most characters that a cut description has, with the ellipsis.
    private static let cutDescriptionLength = 200

    /// The number of characters of a description that is too long for the
    /// cut form to keep.
    private static let longDescriptionLength = 300

    /// A limit that each list of these tests fits.
    private static let largeLimit = 100_000

    /// The first agent of the small catalog.
    private static let alpha = AgentsToolDescription.Entry(name: "alpha", description: "Reads the code.")

    /// The second agent of the small catalog.
    private static let beta = AgentsToolDescription.Entry(name: "beta", description: "Writes the tests.")

    /// An agent with no description.
    private static let gamma = AgentsToolDescription.Entry(name: "gamma", description: nil)

    /// An agent whose description is longer than the cut.
    private static let verbose = AgentsToolDescription.Entry(
        name: "verbose", description: String(repeating: "x", count: longDescriptionLength))

    /// The number of characters that each long name adds to its short name.
    private static let longNameSuffixLength = 60

    /// Three agents whose names do not fit on one line beside the count
    /// line, thus only the partial form can fit a small limit.
    private static let longNamedAgents = ["alpha", "beta", "gamma"].map { shortName in
        AgentsToolDescription.Entry(
            name: shortName + "-" + String(repeating: "x", count: longNameSuffixLength), description: nil)
    }

    // MARK: - The four forms

    @Test func theFullFormGivesOneLineForEachAgent() {
        let description = AgentsToolDescription.make(
            agents: [Self.alpha, Self.beta, Self.gamma], characterLimit: Self.largeLimit)

        #expect(
            description
                == Self.fixedSentences + Self.listSeparator
                + "- alpha: Reads the code.\n- beta: Writes the tests.\n- gamma")
    }

    @Test func theFullFormPutsAMultiLineDescriptionOnOneLine() {
        let spread = AgentsToolDescription.Entry(name: "spread", description: "Reads\n  the   code.")

        let description = AgentsToolDescription.make(agents: [spread], characterLimit: Self.largeLimit)

        #expect(description.hasSuffix(Self.listSeparator + "- spread: Reads the code."))
    }

    @Test func theCutFormCutsEachLongDescriptionTo200Characters() {
        let listStart = "- alpha: Reads the code.\n- verbose: "
        let fullList = listStart + String(repeating: "x", count: Self.longDescriptionLength)
        let cutDescription = String(repeating: "x", count: Self.cutDescriptionLength - 1) + "…"
        let cutList = listStart + cutDescription

        let description = AgentsToolDescription.make(
            agents: [Self.alpha, Self.verbose], characterLimit: fullList.count - 1)

        #expect(cutDescription.count == Self.cutDescriptionLength)
        #expect(description == Self.fixedSentences + Self.listSeparator + cutList)
    }

    @Test func theNamesFormGivesTheNamesOnOneLine() {
        let nameLine = "alpha, beta, gamma"

        let description = AgentsToolDescription.make(
            agents: [Self.alpha, Self.beta, Self.gamma], characterLimit: nameLine.count)

        #expect(description == Self.fixedSentences + Self.listSeparator + nameLine)
    }

    @Test func thePartialFormGivesTheNamesThatFitAndTheCountOfTheOthers() throws {
        let firstName = try #require(Self.longNamedAgents.first?.name)
        let countLine = "2 more agents are not listed. See them with `list agents`."
        let list = firstName + "\n" + countLine

        let description = AgentsToolDescription.make(agents: Self.longNamedAgents, characterLimit: list.count)

        #expect(description == Self.fixedSentences + Self.listSeparator + list)
    }

    @Test func thePartialFormGivesOnlyTheCountLineWhenNoNameFits() {
        let countLine = "3 more agents are not listed. See them with `list agents`."

        let description = AgentsToolDescription.make(agents: Self.longNamedAgents, characterLimit: countLine.count)

        #expect(description == Self.fixedSentences + Self.listSeparator + countLine)
    }

    // MARK: - The empty catalog

    @Test func anEmptyCatalogGivesTheNoAgentsLine() {
        let description = AgentsToolDescription.make(agents: [], characterLimit: Self.largeLimit)

        #expect(description == Self.fixedSentences + Self.listSeparator + Self.noAgentsLine)
    }

    // MARK: - The fixed sentences

    @Test(arguments: [largeLimit, 1, 0])
    func theFixedSentencesAreCompleteAtEachLimit(limit: Int) {
        let description = AgentsToolDescription.make(
            agents: [Self.alpha, Self.beta, Self.verbose], characterLimit: limit)

        #expect(description.hasPrefix(Self.fixedSentences + Self.listSeparator))
    }

    // MARK: - The tool

    @Test func theToolDescriptionHoldsNoAgentThatTheModelCannotStart() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let description = harness.tool.description

        #expect(description.hasPrefix(Self.fixedSentences))
        #expect(description.contains("- code-reviewer: "))
        #expect(description.contains("- internal-helper: "))
        #expect(description.contains("- lead: "))
        #expect(description.contains("- test-writer: "))
        #expect(!description.contains("release-manager"))
    }

    @Test func theToolDescriptionHoldsOnlyTheAllowedNames() async throws {
        let harness = try await AgentsToolHarness.make(allowedNames: ["code-reviewer", "test-writer"])
        defer { try? harness.delete() }

        let description = harness.tool.description

        #expect(description.contains("- code-reviewer: "))
        #expect(description.contains("- test-writer: "))
        #expect(!description.contains("- internal-helper"))
        #expect(!description.contains("- lead"))
        #expect(!description.contains("release-manager"))
    }

    @Test func theCharacterLimitReachesTheToolDescription() async throws {
        let nameLine = "code-reviewer, internal-helper, lead, test-writer"
        let harness = try await AgentsToolHarness.make(catalogCharacterLimit: nameLine.count)
        defer { try? harness.delete() }

        #expect(harness.tool.description == Self.fixedSentences + Self.listSeparator + nameLine)
    }

    @Test func theToolDescriptionOfAnEmptyCatalogHoldsTheNoAgentsLine() async throws {
        let (harness, layer) = try await AgentsToolHarness.makeEmpty()
        defer {
            try? harness.delete()
            try? layer.delete()
        }

        #expect(harness.tool.description == Self.fixedSentences + Self.listSeparator + Self.noAgentsLine)
    }
}
