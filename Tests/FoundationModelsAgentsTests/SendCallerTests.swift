@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins `send caller` and its noun alias `send parent` (plan.md §9.1): a run
/// sends a message to the session that started it, and the run continues.
/// The calling session gets the message as mail, and the Router starts an
/// answer for it. `send agent` with the id of the calling session does the
/// same.
///
/// The root session is the caller. It is on the `flash` slot, and the `lead`
/// run that it starts is on the `standard` slot. A slot has one generation
/// queue, and a child that waits on a gate holds the queue of its slot. Thus
/// the root session can answer the message mail while the child waits.
/// `lead` has an `Agent` grant, thus its tool is a full tool with a caller
/// link.
@Suite("send caller")
struct SendCallerTests {
    /// The agent of each child run.
    private static let lead = NestedRunTests.lead

    /// The key of the play of the root session. It is its instructions.
    private static let rootKey = "send-caller-root-key"

    /// The prompt of the root session.
    private static let rootPrompt = "Give the work to an agent."

    /// The answer of the first answer of the root session.
    private static let rootText = "I started an agent."

    /// The prompt of the child run. It is also the key of its play.
    private static let childPrompt = "send-caller-child-key: divide the task"

    /// The final text of the child run.
    private static let childText = "The task is done."

    /// The message that the child sends to its caller.
    private static let message = "send-caller-message: the parser has a second entry point"

    /// A message that holds no text, in the escaped form of a JSON string.
    private static let blankMessageJSON = #" \n\t "#

    /// The corrective of `send caller` for a run with no caller, word for
    /// word from the task.
    private static let noCallerText = "You have no caller."

    /// The JSON arguments of the `start agent` call of the root session.
    private static let startArguments =
        #"{"op": "start agent", "name": "\#(lead)", "prompt": "\#(childPrompt)"}"#

    /// The script of the root session and of one child run.
    ///
    /// The root session starts the child, answers, and then answers each
    /// mail with the text of the mail prompt.
    ///
    /// - Parameter childSteps: The steps of the play of the child.
    /// - Returns: The script.
    private static func script(childSteps: [ScriptedAgentStep]) -> ScriptedAgentScript {
        ScriptedAgentScript([
            ScriptedAgentPlay(
                key: rootKey,
                steps: [
                    .agentsToolCall(startArguments), .finalText(rootText), .finalTextOfLastPrompt, .finalTextOfLastPrompt
                ]),
            ScriptedAgentPlay(key: childPrompt, steps: childSteps)
        ])
    }

    /// Runs the root session with a child whose first step sends a message
    /// to its caller, and that waits on `gate` after it. The root session
    /// gets the message as mail and answers it. Then the test opens the gate,
    /// the child ends, and the root session answers its final message.
    ///
    /// - Parameters:
    ///   - sendStep: The step of the child that sends the message.
    ///   - setUp: Sets the deferred arguments of the step with the root
    ///     session, before its first message.
    /// - Returns: The events of the root session in order, and the run.
    /// - Throws: The error of the harness, of the root session, or of
    ///   `#require` when the events end too soon.
    private static func runWithMessage(
        sendStep: ScriptedAgentStep, setUp: (any RoutedSession) -> Void = { _ in }
    ) async throws -> (events: [RootSessionEvent], run: AgentRun, toolOutputs: [String]) {
        let gate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(
            script: script(childSteps: [sendStep, .wait(gate), .finalText(childText)]))
        defer { try? harness.delete() }
        let root = harness.makeRootSession(instructions: rootKey, slot: \.flash)
        setUp(root)
        var events = await RootSessionEvent.iterator(of: root)

        _ = try await root.respond(to: rootPrompt)
        let runMessage = try #require(await events.next())
        let messageAnswer = try #require(await events.next())
        gate.open()
        let finalAnswer = try #require(await events.next())
        await harness.tool.context.startedRuns.waitForStarts()
        let run = try await NestedRunTests.onlyRun(of: harness.runner, caller: root.id)
        await root.close()

        return ([runMessage, messageAnswer, finalAnswer], run, harness.runHarness.script.toolOutputs)
    }

    /// `true` when `event` is a `runMessage` event whose detail is
    /// ``message``.
    ///
    /// - Parameter event: An event of the root session.
    /// - Returns: `true` for that event.
    private static func isMessageEvent(_ event: RootSessionEvent) -> Bool {
        if case .runMessage(let detail) = event { return detail == message }
        return false
    }

    /// `true` when `event` is a mail answer whose reply holds `text`.
    ///
    /// - Parameters:
    ///   - event: An event of the root session.
    ///   - text: The text that the reply must hold.
    /// - Returns: `true` for that event.
    private static func isMailAnswer(_ event: RootSessionEvent, holding text: String) -> Bool {
        if case .mailAnswer(let reply) = event { return reply.contains(text) }
        return false
    }

    @Test("a running child that sends a message to its caller causes an answer in the caller, and then ends",
          .timeLimit(.minutes(1)))
    func sendCallerReachesTheCallerAsMail() async throws {
        let (events, run, toolOutputs) = try await Self.runWithMessage(
            sendStep: .agentsToolCall(AgentsToolArguments.sendCaller(message: Self.message)))

        #expect(events.count == 3)
        #expect(Self.isMessageEvent(events[0]))
        #expect(Self.isMailAnswer(events[1], holding: Self.message))
        #expect(Self.isMailAnswer(events[2], holding: run.report))
        #expect(run.state == .finished(Self.childText))
        #expect(toolOutputs.contains(AgentsToolText.messageSentToCaller))
    }

    @Test("send agent with the id of the caller session sends the message to the caller",
          .timeLimit(.minutes(1)))
    func sendAgentWithTheCallerIDReachesTheCaller() async throws {
        let send = ScriptedArguments()
        let (events, run, _) = try await Self.runWithMessage(
            sendStep: .deferredToolCall(name: ToolVocabulary.agentsToolName, arguments: send),
            setUp: { root in
                send.set(
                    AgentsToolArguments.sendAgent(
                        id: " \(root.id.description.lowercased()) ", message: Self.message))
            })

        #expect(events.count == 3)
        #expect(Self.isMessageEvent(events[0]))
        #expect(Self.isMailAnswer(events[1], holding: Self.message))
        #expect(run.state == .finished(Self.childText))
    }

    @Test("send parent resolves to send caller")
    func sendParentResolvesToSendCaller() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let answer = try await harness.call("send parent", ["message": Self.message])

        #expect(answer == Self.noCallerText)
    }

    @Test("a host-started run with a full tool gets the no-caller corrective", .timeLimit(.minutes(1)))
    func hostStartedRunHasNoCaller() async throws {
        let harness = try await AgentsToolHarness.make(
            script: Self.script(childSteps: [
                .agentsToolCall(AgentsToolArguments.sendCaller(message: Self.message)), .finalText(Self.childText)
            ]))
        defer { try? harness.delete() }

        let run = try await harness.runHarness.start(
            Self.lead, prompt: Self.childPrompt, agentsTool: AgentRun.agentsTool(of: harness.runner))
        let result = try await run.result()

        #expect(result == Self.childText)
        #expect(harness.runHarness.script.toolOutputs == [Self.noCallerText])
    }

    @Test("send caller with a blank message is a corrective", .timeLimit(.minutes(1)))
    func sendCallerWithABlankMessageIsCorrective() async throws {
        let harness = try await AgentsToolHarness.make(
            script: Self.script(childSteps: [
                .agentsToolCall(AgentsToolArguments.sendCaller(message: Self.blankMessageJSON)),
                .finalText(Self.childText)
            ]))
        defer { try? harness.delete() }
        let root = harness.makeRootSession(instructions: Self.rootKey, slot: \.flash)
        var events = await RootSessionEvent.iterator(of: root)

        _ = try await root.respond(to: Self.rootPrompt)
        let firstEvent = try #require(await events.next())
        await harness.tool.context.startedRuns.waitForStarts()
        let run = try await NestedRunTests.onlyRun(of: harness.runner, caller: root.id)
        await root.close()

        #expect(Self.isMailAnswer(firstEvent, holding: run.report))
        #expect(harness.runHarness.script.toolOutputs.contains(AgentsToolText.blankMessage))
    }
}
