@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins the final message of a run (plan.md §9.2, §16): a scripted root
/// session calls `start agent`, the call returns at once and posts nothing,
/// and the run posts one `.completed` event through the `ToolContext` of the
/// call when it ends. The Router journals the post, emits `runSettled`, and
/// the next prompt of the root session reads it.
///
/// The root session runs on the `standard` slot, and the child
/// (code-reviewer) runs on the `flash` slot. Each slot has its own
/// generation gate, thus a gated turn on each slot can wait at one time.
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

    /// The second prompt of the root session.
    private static let nextPrompt = "Read the results of the agents."

    /// The answer of the first turn of the root session.
    private static let rootText = "I started a reviewer."

    /// The answer of the second turn of the root session.
    private static let nextText = "The reviewer finished."

    /// The prompt of the child run. It is also the key of its play.
    private static let childPrompt = "final-child-key: review the parser"

    /// The final text of the child run.
    private static let childText = "The parser is correct."

    /// The count of copies of ``childText`` in the long final text.
    private static let longTextCopies = 300

    /// The arguments of the scripted `start agent` call of the root session.
    private static let startArguments = """
        {"op": "start agent", "name": "code-reviewer", "prompt": "\(childPrompt)"}
        """

    /// Makes a script: the root session starts the child, waits on
    /// `rootGate` when one is given, then answers two turns. The child plays
    /// `childSteps`.
    ///
    /// - Parameters:
    ///   - childSteps: The steps of the play of the child run.
    ///   - rootGate: A gate that holds the first turn of the root session
    ///     after the tool call, or `nil`.
    /// - Returns: The script.
    private static func script(
        child childSteps: [ScriptedAgentStep], rootGate: ScriptedGate? = nil
    ) -> ScriptedAgentScript {
        let gateSteps = rootGate.map { [ScriptedAgentStep.wait($0)] } ?? []
        let rootSteps =
            [ScriptedAgentStep.toolCall(name: ToolVocabulary.agentsToolName, argumentsJSON: startArguments)]
            + gateSteps + [.finalText(rootText), .finalText(nextText)]
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

    /// Gives the `.completed` events that the transcript of the root session
    /// journaled for the tool call that started `run`.
    ///
    /// - Parameters:
    ///   - root: The root session.
    ///   - run: The run.
    /// - Returns: The events, in file order.
    /// - Throws: The error of `#require` when the run has no context, or the
    ///   error of the read.
    private static func journaledPosts(of run: AgentRun, in root: any RoutedSession) throws -> [OperationEvent] {
        let token = try #require(run.context?.completionToken)
        return try RecordedTranscript.operationEvents(in: root.recordingDirectory)
            .filter { $0.kind == .completed && $0.correlationID == token }
    }

    /// Gives the first `runSettled` event of `events`.
    ///
    /// - Parameter events: The session events of the root session.
    /// - Returns: The event, or `nil` when the stream ends first.
    private static func firstRunSettled(in events: AsyncStream<SessionEvent>) async -> OperationEvent? {
        for await event in events {
            if case .runSettled(let settled) = event {
                return settled
            }
        }
        return nil
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

    @Test("start agent returns before the gated child turn ends, and posts nothing during its call",
        .timeLimit(.minutes(1)))
    func startReturnsBeforeChildEndsAndPostsNothing() async throws {
        let childGate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(
            script: Self.script(child: [.wait(childGate), .finalText(Self.childText)]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)

        let answer = try await root.respond(to: Self.rootPrompt)
        await childGate.waitForArrival()
        let run = try await Self.childRun(in: harness, of: root)
        let postsWhileRunning = try Self.journaledPosts(of: run, in: root)
        childGate.open()
        _ = try await run.result()
        let postsAfterFinish = try Self.journaledPosts(of: run, in: root)
        await root.close()

        #expect(answer == Self.rootText)
        #expect(run.caller == root.id)
        #expect(postsWhileRunning.isEmpty)
        #expect(postsAfterFinish.map(\.detail) == [Self.childText])
        #expect(postsAfterFinish.map(\.outcome) == [.succeeded])
        #expect(postsAfterFinish.map(\.tool) == [ToolVocabulary.agentsToolName])
    }

    @Test(
        "the final message is the only post, holds more than 4096 characters, emits runSettled, and is read next",
        .timeLimit(.minutes(1)))
    func finalMessageIsOnlyPostAndNextPromptReadsIt() async throws {
        let longText = String(repeating: Self.childText + " ", count: Self.longTextCopies)
        let harness = try await AgentsToolHarness.make(script: Self.script(child: [.finalText(longText)]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)
        let events = await root.streamSessionEvents()

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        let run = try await Self.childRun(in: harness, of: root)
        _ = try await run.result()
        let settled = await Self.firstRunSettled(in: events)
        let posts = try Self.journaledPosts(of: run, in: root)
        let next = try await root.respond(to: Self.nextPrompt)
        let nextPrompt = try #require(harness.runHarness.script.prompts.last)
        await root.close()

        #expect(longText.count > ToolContext.terminalDetailTailLimit)
        #expect(settled?.detail == longText)
        #expect(settled?.kind == .completed)
        #expect(posts.map(\.detail) == [longText])
        #expect(next == Self.nextText)
        #expect(nextPrompt.contains(longText))
        #expect(nextPrompt.contains(Self.nextPrompt))
    }

    @Test("a failed run posts one .completed with the failed outcome and the reason", .timeLimit(.minutes(1)))
    func failedRunPostsOneCompleted() async throws {
        let harness = try await AgentsToolHarness.make(script: Self.script(child: [.fail(ScriptedFailure.broken)]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        let run = try await Self.childRun(in: harness, of: root)
        let failureText = try #require(Self.modelFailureText(await run.finalState()))
        let posts = try Self.journaledPosts(of: run, in: root)
        await root.close()

        #expect(posts.map(\.detail) == ["Agent code-reviewer (\(run.id)) failed: the model failed: \(failureText)."])
        #expect(posts.map(\.outcome) == [.failed])
    }

    @Test("a cancelled run posts one .completed with the cancelled outcome", .timeLimit(.minutes(1)))
    func cancelledRunPostsOneCompleted() async throws {
        let childGate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(
            script: Self.script(child: [.wait(childGate), .finalText(Self.childText)]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        await childGate.waitForArrival()
        let run = try await Self.childRun(in: harness, of: root)
        await harness.runner.cancelRuns(caller: root.id)
        let state = await run.finalState()
        let posts = try Self.journaledPosts(of: run, in: root)
        await root.close()

        #expect(state == .cancelled)
        #expect(posts.map(\.detail) == ["Agent code-reviewer (\(run.id)) was cancelled."])
        #expect(posts.map(\.outcome) == [.cancelled])
    }

    @Test("a post that arrives during a turn of the calling session stays staged, and the next prompt reads it",
        .timeLimit(.minutes(1)))
    func postDuringCallerTurnStaysStaged() async throws {
        let rootGate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(
            script: Self.script(child: [.finalText(Self.childText)], rootGate: rootGate))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)

        let firstTurn = Task { try await root.respond(to: Self.rootPrompt) }
        await rootGate.waitForArrival()
        let run = try await Self.childRun(in: harness, of: root)
        _ = try await run.result()
        rootGate.open()
        let first = try await firstTurn.value
        let next = try await root.respond(to: Self.nextPrompt)
        let prompts = harness.runHarness.script.prompts
        await root.close()

        #expect(first == Self.rootText)
        #expect(next == Self.nextText)
        #expect(prompts.filter { $0.contains(Self.childText) }.count == 1)
        #expect(prompts.last?.contains(Self.childText) == true)
    }
}
