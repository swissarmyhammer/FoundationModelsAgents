@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins `send agent` (plan.md §9.1): a caller sends a message to a run that it
/// started. A run in operation gets the message and answers it before it
/// ends. A run that ended gets no message, and the call gives a corrective.
///
/// The tests with no root session call the tool outside a Router session, as
/// a command line does: the caller is `nil`, the same as the caller of the
/// run. The token test and the caller test use root sessions on the
/// `standard` slot. The child run of code-reviewer runs on the `flash` slot.
@Suite("send agent")
struct SendAgentTests {
    /// A failure that a scripted step throws.
    private enum ScriptedFailure: Error {
        /// The model call of the step failed.
        case broken
    }

    /// The agent of each child run.
    private static let reviewer = AgentRunTests.reviewer

    /// The prompt of each child run. It is also the key of its play.
    private static let prompt = "send-agent-child-key: review the diff"

    /// The message that each test sends to a run.
    private static let message = "send-agent-message: also check the error paths"

    /// A message that holds no text.
    private static let blankMessage = " \n\t "

    /// The reply of the answer of the task prompt of a child run.
    private static let taskReply = "I reviewed the diff."

    /// The key of the play of root session A. It is its instructions.
    private static let rootAKey = "send-agent-root-a"

    /// The key of the play of root session B. It is its instructions.
    private static let rootBKey = "send-agent-root-b"

    /// The prompt of each root session.
    private static let rootPrompt = "Give the review to an agent."

    /// The answer of each turn of a root session.
    private static let rootText = "Done."

    /// The JSON arguments of a scripted `start agent` call for the child.
    private static let startArguments =
        #"{"op": "start agent", "name": "\#(reviewer)", "prompt": "\#(prompt)"}"#

    /// A script with one play for the child run.
    ///
    /// - Parameter steps: The steps of the play of the child.
    /// - Returns: The script.
    private static func childScript(_ steps: [ScriptedAgentStep]) -> ScriptedAgentScript {
        ScriptedAgentScript([ScriptedAgentPlay(key: prompt, steps: steps)])
    }

    /// The steps of a child whose task turn waits on `gate`. The child then
    /// answers its task prompt with ``taskReply``, and answers a message with
    /// the text of the message prompt.
    ///
    /// - Parameter gate: The gate of the task turn.
    /// - Returns: The steps.
    private static func gatedChildSteps(_ gate: ScriptedGate) -> [ScriptedAgentStep] {
        [.wait(gate), .finalText(taskReply), .finalTextOfLastPrompt]
    }

    /// The JSON arguments of a `send agent` call.
    ///
    /// - Parameter id: The id that the call names.
    /// - Returns: The JSON text.
    private static func sendArguments(id: String) -> String {
        #"{"op": "send agent", "id": "\#(id)", "message": "\#(message)"}"#
    }

    /// The fields of a `send agent` payload.
    ///
    /// - Parameters:
    ///   - run: The run that the call names.
    ///   - text: The message of the call.
    /// - Returns: The fields.
    private static func sendFields(to run: AgentRun, text: String = message) -> [String: String] {
        ["id": run.id.description, "message": text]
    }

    /// `true` when `text` is the prompt of ``message`` from the caller.
    ///
    /// - Parameter text: The text of a prompt or a reply.
    /// - Returns: `true` when the text holds the caller prefix and the
    ///   message.
    private static func isCallerMessage(_ text: String) -> Bool {
        text.contains(AgentsToolText.callerMessagePrefix) && text.contains(message)
    }

    /// The answer of `send agent` for a message that the run accepted.
    ///
    /// - Parameter run: The run that got the message.
    /// - Returns: The text.
    private static func sentText(to run: AgentRun) -> String {
        "The message was sent to \(run.subject). Its final message comes to you as mail."
    }

    /// The corrective of `send agent` for a run that ended.
    ///
    /// - Parameters:
    ///   - run: The run that ended.
    ///   - state: The word of the final state of the run.
    /// - Returns: The text.
    private static func endedText(of run: AgentRun, state: String) -> String {
        "The run \(run.id) ended (\(state)), and it gets no more messages. Start a new run."
    }

    /// Starts one child run through the tool outside a Router session.
    ///
    /// - Parameter harness: The harness of the tool.
    /// - Returns: The run.
    /// - Throws: The error of the tool, or of `#require` when the tool
    ///   started no run.
    private static func startChild(in harness: AgentsToolHarness) async throws -> AgentRun {
        _ = try await harness.call("start agent", ["name": reviewer, "prompt": prompt])
        return try #require(await harness.runner.runs(caller: nil).first)
    }

    /// Makes a root session over the `standard` slot, with the `agents` tool
    /// of the harness.
    ///
    /// - Parameters:
    ///   - key: The key of the play of the session. It is the instructions.
    ///   - harness: The harness of the tool.
    /// - Returns: The root session.
    private static func rootSession(_ key: String, of harness: AgentsToolHarness) -> any RoutedSession {
        harness.runHarness.profile.standard.makeSession(instructions: key, tools: [harness.tool])
    }

    /// Gives the one run that a root session started, after the body of each
    /// open `start agent` call added its run.
    ///
    /// - Parameters:
    ///   - harness: The harness of the tool.
    ///   - root: The root session.
    /// - Returns: The run.
    /// - Throws: The error of `#require` when the root session started no run.
    private static func onlyRun(in harness: AgentsToolHarness, of root: any RoutedSession) async throws -> AgentRun {
        await harness.tool.context.startedRuns.waitForStarts()
        let runs = await harness.runner.runs(caller: root.id)
        #expect(runs.count == 1)
        return try #require(runs.first)
    }

    @Test("send agent to a running child is a success, and the child answers the message",
        .timeLimit(.minutes(1)))
    func sendToRunningChildIsDelivered() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(script: Self.childScript(Self.gatedChildSteps(gate)))
        defer { try? harness.delete() }

        let run = try await Self.startChild(in: harness)
        await gate.waitForArrival()
        let answer = try await harness.call("send agent", Self.sendFields(to: run))
        gate.open()
        let result = try await run.result()

        #expect(answer == Self.sentText(to: run))
        #expect(harness.runHarness.script.prompts.contains(where: Self.isCallerMessage))
        #expect(Self.isCallerMessage(result))
    }

    @Test("send agent with the completion token of the pending envelope reaches the run",
        .timeLimit(.minutes(1)))
    func sendWithCompletionTokenIsDelivered() async throws {
        let rootGate = ScriptedGate()
        let childGate = ScriptedGate()
        let send = ScriptedArguments()
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: Self.rootAKey,
                steps: [
                    .toolCall(name: ToolVocabulary.agentsToolName, argumentsJSON: Self.startArguments),
                    .wait(rootGate),
                    .deferredToolCall(name: ToolVocabulary.agentsToolName, arguments: send),
                    .finalText(Self.rootText),
                    .finalTextOfLastPrompt
                ]),
            ScriptedAgentPlay(key: Self.prompt, steps: Self.gatedChildSteps(childGate))
        ])
        let harness = try await AgentsToolHarness.make(script: script)
        defer { try? harness.delete() }
        let root = Self.rootSession(Self.rootAKey, of: harness)

        async let rootAnswer = root.respond(to: Self.rootPrompt)
        await rootGate.waitForArrival()
        let envelope = try #require(harness.runHarness.script.toolOutputs.first)
        let token = try #require(ScriptedTranscriptText.completionToken(in: envelope))
        send.set(Self.sendArguments(id: token))
        rootGate.open()
        _ = try await rootAnswer
        let answer = harness.runHarness.script.toolOutputs.last
        let run = try await Self.onlyRun(in: harness, of: root)
        childGate.open()
        let result = try await run.result()
        await root.close()

        #expect(answer == Self.sentText(to: run))
        #expect(Self.isCallerMessage(result))
    }

    @Test("send agent to a finished run gives the run-ended corrective", .timeLimit(.minutes(1)))
    func sendToFinishedRunIsCorrective() async throws {
        let harness = try await AgentsToolHarness.make(script: Self.childScript([.finalText(Self.taskReply)]))
        defer { try? harness.delete() }

        let run = try await Self.startChild(in: harness)
        _ = try await run.result()
        let answer = try await harness.call("send agent", Self.sendFields(to: run))

        #expect(answer == Self.endedText(of: run, state: "finished"))
        #expect(!harness.runHarness.script.prompts.contains(where: Self.isCallerMessage))
    }

    @Test("send agent to a cancelled run gives the run-ended corrective", .timeLimit(.minutes(1)))
    func sendToCancelledRunIsCorrective() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(script: Self.childScript(Self.gatedChildSteps(gate)))
        defer { try? harness.delete() }

        let run = try await Self.startChild(in: harness)
        await gate.waitForArrival()
        run.cancel()
        #expect(await run.finalState() == .cancelled)
        let answer = try await harness.call("send agent", Self.sendFields(to: run))

        #expect(answer == Self.endedText(of: run, state: "cancelled"))
    }

    @Test("send agent to a failed run gives the run-ended corrective", .timeLimit(.minutes(1)))
    func sendToFailedRunIsCorrective() async throws {
        let harness = try await AgentsToolHarness.make(script: Self.childScript([.fail(ScriptedFailure.broken)]))
        defer { try? harness.delete() }

        let run = try await Self.startChild(in: harness)
        _ = await run.finalState()
        let answer = try await harness.call("send agent", Self.sendFields(to: run))

        #expect(answer == Self.endedText(of: run, state: "failed"))
    }

    @Test("send agent to a run of a different caller gives the unknown-run corrective",
        .timeLimit(.minutes(1)))
    func sendToRunOfOtherCallerIsCorrective() async throws {
        let gate = ScriptedGate()
        let send = ScriptedArguments()
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: Self.rootAKey,
                steps: [
                    .toolCall(name: ToolVocabulary.agentsToolName, argumentsJSON: Self.startArguments),
                    .finalText(Self.rootText),
                    .finalTextOfLastPrompt
                ]),
            ScriptedAgentPlay(
                key: Self.rootBKey,
                steps: [
                    .deferredToolCall(name: ToolVocabulary.agentsToolName, arguments: send),
                    .finalText(Self.rootText)
                ]),
            ScriptedAgentPlay(key: Self.prompt, steps: Self.gatedChildSteps(gate))
        ])
        let harness = try await AgentsToolHarness.make(script: script)
        defer { try? harness.delete() }
        let rootA = Self.rootSession(Self.rootAKey, of: harness)
        let rootB = Self.rootSession(Self.rootBKey, of: harness)

        _ = try await rootA.respond(to: Self.rootPrompt)
        await gate.waitForArrival()
        let run = try await Self.onlyRun(in: harness, of: rootA)
        send.set(Self.sendArguments(id: run.id.description))
        _ = try await rootB.respond(to: Self.rootPrompt)
        let answerOfB = harness.runHarness.script.toolOutputs.last
        gate.open()
        let result = try await run.result()
        await rootA.close()
        await rootB.close()

        #expect(answerOfB == "No run has the id \(run.id). You have no runs.")
        #expect(result == Self.taskReply)
        #expect(!harness.runHarness.script.prompts.contains(where: Self.isCallerMessage))
    }

    @Test("send agent with a blank message is a corrective, and the run gets no message",
        .timeLimit(.minutes(1)))
    func sendBlankMessageIsCorrective() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(script: Self.childScript(Self.gatedChildSteps(gate)))
        defer { try? harness.delete() }

        let run = try await Self.startChild(in: harness)
        await gate.waitForArrival()
        let answer = try await harness.call("send agent", Self.sendFields(to: run, text: Self.blankMessage))
        gate.open()
        let result = try await run.result()

        #expect(answer == AgentsToolText.blankMessage)
        #expect(result == Self.taskReply)
    }
}
