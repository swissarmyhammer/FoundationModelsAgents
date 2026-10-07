import FoundationModelsRouter
import Testing

@testable import FoundationModelsAgents

/// A root session and its `lead` run that send one message to each other,
/// with `send caller` and with `send agent`.
///
/// The telemetry suites use this exchange to read the record of each message.
/// The exchange goes in this order:
///
/// 1. The root session starts `lead` and answers.
/// 2. `lead` sends the message to its caller (`send caller`), and then waits
///    on a gate. The root session gets the message as mail and answers it.
/// 3. The root session gets a second prompt and sends the message to `lead`
///    (`send agent`).
/// 4. The gate opens. `lead` ends its task turn, answers the message, and
///    ends. The root session answers the final message of `lead`.
///
/// The root session is on the `flash` slot, and `lead` is on the `standard`
/// slot. Thus the root session can answer while `lead` waits on its gate.
struct MessageExchange {
    /// The key of the play of the root session. It is its instructions.
    private static let rootKey = "message-exchange-root-key"

    /// The first prompt of the root session.
    private static let rootPrompt = "Give the work to an agent."

    /// The second prompt of the root session. It causes the `send agent`
    /// call.
    private static let followUpPrompt = "Tell the agent one more thing."

    /// The text of each answer of the root session to a prompt.
    private static let rootText = "Done."

    /// The prompt of `lead`. It is also the key of its play.
    private static let leadPrompt = "message-exchange-lead-key: divide the task"

    /// The final text of the task turn of `lead`.
    private static let leadText = "The task is done."

    /// The run of `lead`.
    let lead: AgentRun

    /// Runs the exchange, and waits for `lead` to end.
    ///
    /// - Parameters:
    ///   - message: The message that each side sends. It must be valid in a
    ///     JSON string with no escape.
    ///   - telemetry: The telemetry of the router and of each run.
    /// - Returns: The exchange.
    /// - Throws: The error of the harness, of the root session, or of
    ///   `#require` when the events of the root session end too soon.
    static func run(message: String, telemetry: HarnessTelemetry) async throws -> MessageExchange {
        let gate = ScriptedGate()
        let send = ScriptedArguments()
        let harness = try await AgentsToolHarness.make(
            script: script(message: message, gate: gate, send: send), telemetry: telemetry)
        defer { try? harness.delete() }
        let root = harness.makeRootSession(instructions: rootKey, slot: \.flash)
        var events = await RootSessionEvent.iterator(of: root)

        _ = try await root.respond(to: rootPrompt)
        _ = try #require(await events.next())
        _ = try #require(await events.next())
        await harness.tool.context.startedRuns.waitForStarts()
        let lead = try await NestedRunTests.onlyRun(of: harness.runner, caller: root.id)
        send.set(AgentsToolArguments.sendAgent(id: lead.id.description, message: message))
        _ = try await root.respond(to: followUpPrompt)
        gate.open()
        _ = try #require(await events.next())
        _ = await lead.finalState()
        await root.close()
        return MessageExchange(lead: lead)
    }

    /// The script of the root session and of `lead`.
    ///
    /// - Parameters:
    ///   - message: The message that each side sends.
    ///   - gate: The gate that `lead` waits on after its `send caller` call.
    ///   - send: The deferred arguments of the `send agent` call of the root
    ///     session.
    /// - Returns: The script.
    private static func script(
        message: String, gate: ScriptedGate, send: ScriptedArguments
    ) -> ScriptedAgentScript {
        ScriptedAgentScript([
            ScriptedAgentPlay(
                key: rootKey,
                steps: [
                    NestedRunTests.startStep(NestedRunTests.lead, prompt: leadPrompt), .finalText(rootText),
                    .finalTextOfLastPrompt,
                    .deferredToolCall(name: ToolVocabulary.agentsToolName, arguments: send), .finalText(rootText),
                    .finalTextOfLastPrompt
                ]),
            ScriptedAgentPlay(
                key: leadPrompt,
                steps: [
                    .agentsToolCall(AgentsToolArguments.sendCaller(message: message)), .wait(gate),
                    .finalText(leadText), .finalTextOfLastPrompt
                ])
        ])
    }
}
