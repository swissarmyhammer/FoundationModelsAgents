import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

extension LiveSuites {
    /// The full circle of one delegation on real models (plan.md §9, §15).
    ///
    /// A root session on the `standard` slot has the `agents` tool. Its model
    /// calls `start agent`, and the call answers at once. The sub-agent runs
    /// on the `standard` slot after the turn of the root ends. It calls
    /// ``LiveWordTool``, and answers with the secret word. The larger model
    /// follows the tool instruction better than the `flash` model. Its final
    /// message comes to the root as mail, and the root answers that mail. The
    /// reply of that answer holds the secret word. Only the tool knows the
    /// word, thus the root can give it only from the final message.
    /// Then `check agent`, called as the root session, gives the same text.
    ///
    /// One case gives the root the exact JSON of the call. The other case
    /// names the task only. In that case the root learns how to start the
    /// agent from the description of the `agents` tool. Each prompt ends with
    /// ``LiveHarness/waitInstruction``, thus the root does not guess a word
    /// before the final message comes.
    ///
    /// `check agent` answers only for a run of the caller. The test keeps the
    /// `ToolContext` of the `start agent` call of the root with
    /// ``LiveAgentsToolProbe``, and calls `check agent` in that context. Thus
    /// the check does not depend on a choice of the model.
    ///
    /// The test asserts on recorded facts: the calls of the tool, the
    /// `agentSpawn` of the sub-agent, and the posts in the root transcript.
    /// The root transcript also holds no tool call that the Router rejected,
    /// thus the first tool call of the root is a call of `agents`, and not a
    /// call of an op name such as "start agent" as a tool.
    /// The test reads the root transcript only after `close()` of the root
    /// session, thus the transcript is complete (``LiveRecording``).
    @Suite("Full circle", .serialized, .timeLimit(LiveProfile.timeLimit))
    struct FullCircleTests {
        /// The sub-agent.
        private static let finder = "word-finder"

        /// The task that the root gives to the sub-agent.
        private static let task = "Find the secret word."

        @Test("start agent, a tool of the sub-agent, the final message, the next turn, and check agent")
        func delegationGoesFullCircle() async throws {
            let call = try LiveHarness.agentsCallText([
                "op": LiveHarness.startOperation, "name": Self.finder, "prompt": Self.task
            ])
            try await Self.goFullCircle(rootPrompt: "\(call) \(LiveHarness.waitInstruction)")
        }

        @Test("The root starts the sub-agent from the tool description, with no JSON in the prompt")
        func toolDescriptionTellsHowToStart() async throws {
            try await Self.goFullCircle(
                rootPrompt: "Ask the \(Self.finder) agent for the secret word. \(LiveHarness.waitInstruction)")
        }

        /// Runs one delegation from `rootPrompt` to the reply of the root, and
        /// checks each step.
        ///
        /// - Parameter rootPrompt: The first prompt of the root session. It
        ///   makes the root start ``finder``.
        /// - Throws: The error of the harness, of a turn, of a read of the
        ///   recording, or of `#require`.
        private static func goFullCircle(rootPrompt: String) async throws {
            let wordTool = LiveWordTool()
            let agents = [
                LiveAgentFile.path(of: finder): LiveAgentFile.text(
                    id: finder,
                    description: "Finds the secret word with a tool.",
                    fields: ["model: standard", "tools: \(LiveWordTool.toolName)"],
                    body: LiveAgentFile.toolWordBody(toolName: LiveWordTool.toolName))
            ]

            try await LiveHarness.withHarness(agents: agents, tools: [wordTool]) { harness in
                let agentsTool = try await harness.makeAgentsTool()
                let probe = LiveAgentsToolProbe(wrapping: agentsTool)
                let root = harness.makeRootSession(tools: [probe])
                var finalMailReplies = await Self.finalMailReplies(of: root).makeAsyncIterator()
                _ = try await root.respond(to: rootPrompt)
                let finderRun = try LiveHarness.run(of: finder, in: await harness.runner.runs(caller: root.id))
                let text = try await finderRun.result()
                let reply = await finalMailReplies.next()
                await root.close()
                let spawn = try #require(try LiveRecording.session(of: finderRun).agentSpawn)
                let startContext = try #require(
                    probe.callContexts.first { $0.completionToken == spawn.parentToolCallId })
                let check = try await ToolContext.$current.withValue(startContext) {
                    try await harness.call(agentsTool, LiveHarness.checkOperation, ["id": finderRun.id.description])
                }

                let posted = try LiveRecording.operationEvents(of: .toolOutput, in: root.recordingDirectory)
                    .filter { $0.kind == .completed && $0.correlationID == spawn.parentToolCallId }
                let read = try LiveRecording.operationEvents(of: .prompt, in: root.recordingDirectory)
                    .filter { $0.kind == .completed && $0.correlationID == spawn.parentToolCallId }
                let rejected = try LiveRecording.rejectedToolCallPrompts(in: root.recordingDirectory)
                let detail = "Agent \(finder) (\(finderRun.id)) finished.\n\n\(text)"

                #expect(rejected.isEmpty, "The Router rejected a tool call of the root: \(rejected)")
                #expect(wordTool.callCount > 0)
                #expect(text.localizedCaseInsensitiveContains(LiveWordTool.word), "The final text was: \(text)")
                #expect(startContext.sessionID == root.id)
                #expect(spawn.parentSessionId == root.id)
                #expect(posted.map(\.detail) == [detail])
                #expect(read.map(\.detail) == [detail])
                #expect(check == detail, "The check gave: \(check)")
                #expect(
                    reply?.localizedCaseInsensitiveContains(LiveWordTool.word) == true,
                    "The reply of the root was: \(String(describing: reply))")
            }
        }

        /// Gives the reply of each answer of `root` that reads the final
        /// message of a run.
        ///
        /// A sub-agent can also send messages to the root with `send caller`.
        /// The root answers each message mail, and that reply comes before
        /// the final message. Thus the first answer to mail is not always the
        /// answer to the final message.
        ///
        /// The Router posts the final message as a `.runSettled` event. The
        /// next submission start after that event takes the final message.
        /// That submission starts a new answer, or continues an answer that is
        /// in progress. Thus the first answer to mail that has a submission
        /// start after the `.runSettled` event reads the final message.
        ///
        /// - Parameter root: The root session.
        /// - Returns: The replies, in the order of the answers.
        private static func finalMailReplies(of root: any RoutedSession) async -> AsyncStream<String> {
            let events = await root.streamSessionEvents()
            return AsyncStream { continuation in
                let task = Task {
                    var isSettled = false
                    var readsFinalMessage = false
                    for await event in events {
                        switch event {
                        case .runSettled:
                            isSettled = true
                        case .submissionStarted where isSettled:
                            readsFinalMessage = true
                        case .answered(let answer) where answer.messageIds.isEmpty && readsFinalMessage:
                            readsFinalMessage = false
                            continuation.yield(answer.reply)
                        default:
                            break
                        }
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
}
