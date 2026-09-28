@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins the final message of a run (plan.md §9.2, §16): a scripted root
/// session calls `start agent`, and the call answers at once with the pending
/// envelope of the Router. The background body of the call waits for the
/// run, and gives the final message text of the run as the detail of the
/// Router run. The Router records the terminal, emits `runSettled`, and
/// gives the final message to the root session as mail. The pump of the
/// Router starts the answer to that mail with no call of the test.
@Suite("Final message")
struct FinalMessageTests {
    /// A failure that a scripted step throws.
    private enum ScriptedFailure: Error {
        /// The model call of the step failed.
        case broken
    }

    /// The key of the play of the root session. It is the instructions of
    /// the root session.
    private static let rootKey = "final-root-play-key"

    /// The first prompt of the root session.
    private static let rootPrompt = "Give the review to an agent."

    /// The answer of the first answer of the root session.
    private static let rootText = "I started a reviewer."

    /// The prompt of the child run. It is also the key of its play.
    private static let childPrompt = "final-child-key: review the parser"

    /// The final text of the child run.
    private static let childText = "The parser is correct."

    /// The count of copies of ``childText`` in the long final text.
    private static let longTextCopies = 300

    /// The length that the long final text is above: the tail limit that
    /// an older Router put on the detail of a terminal.
    private static let oldDetailLimit = 4096

    /// The mark of a pending envelope of the Router in a tool output.
    private static let pendingMark = #""pending":true"#

    /// The arguments of the scripted `start agent` call of the root session.
    private static let startArguments = """
        {"op": "start agent", "name": "code-reviewer", "prompt": "\(childPrompt)"}
        """

    /// Makes a script: the root session starts the child, waits on
    /// `rootGate` when one is given, answers, then answers the mail of the
    /// child with that mail. The child plays `childSteps`.
    ///
    /// - Parameters:
    ///   - childSteps: The steps of the play of the child run.
    ///   - rootGate: A gate that holds the first answer of the root session
    ///     after the tool call, or `nil`.
    /// - Returns: The script.
    private static func script(
        child childSteps: [ScriptedAgentStep], rootGate: ScriptedGate? = nil
    ) -> ScriptedAgentScript {
        let gateSteps = rootGate.map { [ScriptedAgentStep.wait($0)] } ?? []
        let rootSteps =
            [ScriptedAgentStep.toolCall(name: ToolVocabulary.agentsToolName, argumentsJSON: startArguments)]
            + gateSteps + [.finalText(rootText), .finalTextOfLastPrompt]
        return ScriptedAgentScript([
            ScriptedAgentPlay(key: rootKey, steps: rootSteps),
            ScriptedAgentPlay(key: childPrompt, steps: childSteps)
        ])
    }

    /// Makes the root session over the `standard` slot, with the `agents`
    /// tool of the harness.
    ///
    /// - Parameter harness: The harness of the tool.
    /// - Returns: The root session.
    private static func rootSession(of harness: AgentsToolHarness) -> any RoutedSession {
        harness.runHarness.profile.standard.makeSession(instructions: rootKey, tools: [harness.tool])
    }

    /// Gives the one run that the root session started.
    ///
    /// - Parameters:
    ///   - harness: The harness of the tool.
    ///   - root: The root session.
    /// - Returns: The run.
    /// - Throws: The error of `#require` when the root session started no run.
    private static func childRun(in harness: AgentsToolHarness, of root: any RoutedSession) async throws -> AgentRun {
        let runs = await harness.runner.runs(caller: root.id)
        #expect(runs.count == 1)
        return try #require(runs.first)
    }

    /// Gives the detail of the final message of a code-reviewer run that
    /// finished with `text`.
    ///
    /// - Parameters:
    ///   - run: The run.
    ///   - text: The reply of the last answer of the run.
    /// - Returns: "Agent code-reviewer (`id`) finished.", a blank line, and
    ///   `text`.
    private static func finishedDetail(of run: AgentRun, text: String) -> String {
        "Agent code-reviewer (\(run.id)) finished.\n\n\(text)"
    }

    /// Gives the text of a model failure.
    ///
    /// - Parameter state: The state of a run.
    /// - Returns: The text of ``AgentRunFailure/modelFailed(_:)``, or `nil`
    ///   for each other state.
    private static func modelFailureText(_ state: AgentRunState) -> String? {
        if case .failed(.modelFailed(let text)) = state {
            return text
        }
        return nil
    }

    @Test("start agent answers with the pending envelope, and the Router records the final message at the end",
        .timeLimit(.minutes(1)))
    func startReturnsPendingEnvelopeAndRouterRecordsFinalMessage() async throws {
        let childGate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(
            script: Self.script(child: [.wait(childGate), .finalText(Self.childText)]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)
        let events = await root.streamSessionEvents()

        let answer = try await root.respond(to: Self.rootPrompt)
        await childGate.waitForArrival()
        let run = try await Self.childRun(in: harness, of: root)
        let postsWhileRunning = try NestedRunTests.posts(of: run, in: root.recordingDirectory)
        childGate.open()
        _ = try await run.result()
        let settled = try await NestedRunTests.settlement(of: run, in: events)
        let postsAfterFinish = try NestedRunTests.posts(of: run, in: root.recordingDirectory)
        await root.close()

        #expect(answer == Self.rootText)
        #expect(run.caller == root.id)
        #expect(harness.runHarness.script.toolOutputs.first?.contains(Self.pendingMark) == true)
        #expect(postsWhileRunning.isEmpty)
        #expect(settled.detail == Self.finishedDetail(of: run, text: Self.childText))
        #expect(postsAfterFinish.map(\.detail) == [Self.finishedDetail(of: run, text: Self.childText)])
        #expect(postsAfterFinish.map(\.outcome) == [.succeeded])
        #expect(postsAfterFinish.map(\.tool) == [ToolVocabulary.agentsToolName])
    }

    @Test(
        "in a host root session, a child that ends at once gives its final message as mail, not in the start answer",
        .timeLimit(.minutes(1)))
    func fastChildOfRootSessionComesAsMail() async throws {
        let harness = try await AgentsToolHarness.make(script: Self.script(child: [.finalText(Self.childText)]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)
        let events = await root.streamSessionEvents()

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        let startAnswer = try #require(harness.runHarness.script.toolOutputs.first)
        try #require(startAnswer.contains(Self.pendingMark), "The start answer was: \(startAnswer)")
        let terminal = try await NestedRunTests.firstSettlement(in: events)
        let run = try await Self.childRun(in: harness, of: root)
        try await NestedRunTests.arrival(ofPromptContaining: Self.childText, in: harness.runHarness.script)
        let mailPrompt = try #require(harness.runHarness.script.prompts.last)
        await root.close()

        #expect(terminal.correlationID == run.context?.completionToken)
        #expect(!startAnswer.contains(Self.childText))
        #expect(mailPrompt.contains(Self.finishedDetail(of: run, text: Self.childText)))
    }

    @Test(
        "the final message holds the whole long text, emits runSettled, and the root answers it as mail",
        .timeLimit(.minutes(1)))
    func longFinalMessageComesWholeAsMail() async throws {
        let longText = String(repeating: Self.childText + " ", count: Self.longTextCopies)
        let harness = try await AgentsToolHarness.make(
            script: Self.script(child: [.finalText(longText)]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)
        let events = await root.streamSessionEvents()

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        let settled = try await NestedRunTests.firstSettlement(in: events)
        let run = try await Self.childRun(in: harness, of: root)
        try await NestedRunTests.arrival(ofPromptContaining: Self.childText, in: harness.runHarness.script)
        let mailPrompt = try #require(harness.runHarness.script.prompts.last)
        let posts = try NestedRunTests.posts(of: run, in: root.recordingDirectory)
        await root.close()
        let detail = Self.finishedDetail(of: run, text: longText)

        #expect(longText.count > Self.oldDetailLimit)
        #expect(settled.detail == detail)
        #expect(settled.kind == .completed)
        #expect(posts.map(\.detail) == [detail])
        #expect(mailPrompt.contains(detail))
    }

    @Test("a failed run gives one final message with the reason", .timeLimit(.minutes(1)))
    func failedRunGivesOneFinalMessage() async throws {
        let harness = try await AgentsToolHarness.make(
            script: Self.script(child: [.fail(ScriptedFailure.broken)]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)
        let events = await root.streamSessionEvents()

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        _ = try await NestedRunTests.firstSettlement(in: events)
        let run = try await Self.childRun(in: harness, of: root)
        let failureText = try #require(Self.modelFailureText(await run.finalState()))
        let posts = try NestedRunTests.posts(of: run, in: root.recordingDirectory)
        await root.close()

        #expect(posts.map(\.detail) == ["Agent code-reviewer (\(run.id)) failed: the model failed: \(failureText)."])
    }

    @Test("a cancelled run gives one final message that tells the cancel", .timeLimit(.minutes(1)))
    func cancelledRunGivesOneFinalMessage() async throws {
        let childGate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(
            script: Self.script(child: [.wait(childGate), .finalText(Self.childText)]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)
        let events = await root.streamSessionEvents()

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        await childGate.waitForArrival()
        let run = try await Self.childRun(in: harness, of: root)
        await harness.runner.cancelRuns(caller: root.id)
        let state = await run.finalState()
        _ = try await NestedRunTests.settlement(of: run, in: events)
        let posts = try NestedRunTests.posts(of: run, in: root.recordingDirectory)
        await root.close()

        #expect(state == .cancelled)
        #expect(posts.map(\.detail) == ["Agent code-reviewer (\(run.id)) was cancelled."])
    }

    @Test("a final message that comes during an answer of the caller waits, and the next submission reads it",
        .timeLimit(.minutes(1)))
    func finalMessageDuringCallerAnswerWaitsForNextSubmission() async throws {
        let rootGate = ScriptedGate()
        let childGate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(
            script: Self.script(child: [.wait(childGate), .finalText(Self.childText)], rootGate: rootGate))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)
        let events = await root.streamSessionEvents()

        let firstAnswer = Task { try await root.respond(to: Self.rootPrompt) }
        await rootGate.waitForArrival()
        await childGate.waitForArrival()
        let run = try await Self.childRun(in: harness, of: root)
        childGate.open()
        _ = try await NestedRunTests.settlement(of: run, in: events)
        rootGate.open()
        let first = try await firstAnswer.value
        try await NestedRunTests.arrival(ofPromptContaining: Self.childText, in: harness.runHarness.script)
        let prompts = harness.runHarness.script.prompts
        await root.close()

        #expect(first == Self.rootText)
        #expect(harness.runHarness.script.toolOutputs.first?.contains(Self.pendingMark) == true)
        #expect(prompts.count(where: { $0.contains(Self.childText) }) == 1)
        #expect(prompts.last?.contains(Self.childText) == true)
    }
}
