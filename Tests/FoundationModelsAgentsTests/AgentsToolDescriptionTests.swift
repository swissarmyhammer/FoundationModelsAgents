import Testing
import ULID

@testable import FoundationModelsAgents

/// Pins the description of the `agents` tool.
///
/// The description has the fixed sentences, which are never cut, then the
/// model-visible agents in the first form that fits the character limit:
/// full lines, descriptions cut to 200 characters, names only, and as many
/// names as fit with a count of the other names. An empty catalog gives one
/// line.
@Suite("Agents tool description")
struct AgentsToolDescriptionTests {
    // MARK: - Constants

    /// The fixed sentences, word for word.
    private static let fixedSentences =
        "An agent is a model session that works in the background. Each agent starts with an empty context "
        + "and sees only the prompt that you give it, so put all that the agent needs in the prompt. "
        + #"To give a task to an agent, call the tool "agents" with the arguments {"op": "start agent", "#
        + #""name": "<name>", "prompt": "<the full task>"}. The value of "op" is an operation of the tool "#
        + #""agents", not the name of a tool. When the agent finishes in a few seconds, the call gives its "#
        + "final message. Else the agent works in the background, and its final message comes to you as a "
        + "new message after you end your answer. Your answer is the text of "
        + "your last turn, so give your final answer after you have the results of the agents that you "
        + "started. You can ask about a run "
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

    // MARK: - The delegation sentence

    /// A small model called the op name "start agent" as the name of a tool,
    /// and the Router rejected that call as `undeclared_tool`. Thus the
    /// delegation sentence names the `agents` tool, and it tells that the
    /// value of `op` is not a tool name.
    @Test func theDelegationSentenceNamesTheToolAndTellsThatTheOpIsNotATool() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }
        let toolReference = #"the tool "\#(harness.tool.name)""#

        let sentence = AgentsToolDescription.delegationSentence

        #expect(sentence.hasPrefix("To give a task to an agent, call \(toolReference) with the arguments "))
        #expect(sentence.hasSuffix(#"The value of "op" is an operation of \#(toolReference), not the name of a tool."#))
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

    // MARK: - The caller sentence

    @Test func aDescriptionWithNoCallerIsNotChanged() {
        #expect(AgentsToolDescription.addingCaller(to: Self.fixedSentences, callerID: nil) == Self.fixedSentences)
    }

    @Test func aDescriptionWithACallerEndsWithTheCallerSentence() {
        let callerID = ULID()

        let description = AgentsToolDescription.addingCaller(to: Self.fixedSentences, callerID: callerID)

        #expect(description == Self.fixedSentences + Self.listSeparator + Self.callerSentence(callerID))
    }

    @Test("the tool of a run with a caller link names the caller id, with each grant",
          .timeLimit(.minutes(1)), arguments: [AgentsToolContext.Grant.full, .messagingOnly])
    func theToolOfARunWithACallerNamesTheCallerID(grant: AgentsToolContext.Grant) async throws {
        let harness = try await AgentsToolHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: Self.rootKey, steps: [Self.probeStep, .finalText(Self.rootText)]),
                ScriptedAgentPlay(key: Self.childPrompt, steps: [.finalText(Self.rootText)])
            ]))
        defer { try? harness.delete() }
        let probe = AgentStartProbe { context in
            try await harness.runHarness.start(AgentRunTests.reviewer, prompt: Self.childPrompt, context: context)
        }
        let root = AgentRunHarness.makeRootSession(
            on: harness.runHarness.profile.standard, instructions: Self.rootKey, tools: [probe])

        _ = try await root.respond(to: Self.rootText)
        let started = try #require(probe.started)
        _ = await started.run.finalState()
        await root.close()
        let call = try #require(started.context)
        let link = AgentsToolContext.CallerLink(call: call, sessionID: call.sessionID)
        let tool = try await AgentsTool.make(
            context: AgentsToolContext(
                runner: harness.runner, allowedNames: nil, parent: nil, callerLink: link, grant: grant))

        #expect(tool.description.hasSuffix(Self.listSeparator + Self.callerSentence(root.id)))
    }

    @Test func makeBeforeTheFirstLoadThrowsCatalogNotLoaded() async throws {
        let runHarness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? runHarness.delete() }
        let registry = AgentRegistry(stack: FixtureLibrary.stack())
        let context = AgentsToolContext(
            runner: AgentRunner(registry: registry, environment: runHarness.environment))

        await #expect(throws: AgentRunnerError.catalogNotLoaded) {
            try await AgentsTool.make(context: context)
        }
        try await registry.load()
        let tool = try await AgentsTool.make(context: context)

        #expect(tool.description.contains("- code-reviewer: "))
    }

    // MARK: - Support of the caller sentence

    /// The key of the play of the root session. It is its instructions.
    private static let rootKey = "description-root-key"

    /// The prompt and the answer of the root session.
    private static let rootText = "Start the review."

    /// The prompt of the run that the probe starts. It is also the key of its
    /// play.
    private static let childPrompt = "description-child-key: review the parser"

    /// The step of the root session that calls the probe tool.
    private static let probeStep = ScriptedAgentStep.toolCall(
        name: AgentStartProbe.toolName, argumentsJSON: #"{"text":"start"}"#)

    /// The caller sentence, word for word from the task of `send caller`.
    ///
    /// - Parameter callerID: The id of the session of the caller.
    /// - Returns: The sentence.
    private static func callerSentence(_ callerID: ULID) -> String {
        "The session that started you has the id \(callerID). "
            + #"Send a message to it with {"op": "send caller", "message": "..."}."#
    }
}
