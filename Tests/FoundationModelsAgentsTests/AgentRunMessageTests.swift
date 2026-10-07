import Foundation
@testable import FoundationModelsAgents
import Testing

/// Pins ``AgentRun/deliver(_:)``: a caller sends a message to a run that it
/// started. The run accepts the message and answers it before it ends, or it
/// tells that it ended. A message never races with the idle rule of the run.
@Suite("Messages to a run")
struct AgentRunMessageTests {
    /// The message that each test sends to a run.
    private static let message = "message-key: also check the error paths"

    /// The reply of the answer of the task prompt.
    private static let taskReply = "I reviewed the diff."

    /// Bytes that are not UTF-8 text.
    private static let invalidUTF8: [UInt8] = [0xFF, 0xFE, 0xFD]

    /// The play of a run that answers its task prompt with ``taskReply``, then
    /// answers the message with the text of the message prompt.
    ///
    /// - Parameter gate: A gate that holds the answer of the message before
    ///   it starts, or `nil` for no hold.
    /// - Returns: The script.
    private static func taskThenMessage(holdingMessageAt gate: ScriptedGate? = nil) -> ScriptedAgentScript {
        let hold = gate.map { [ScriptedAgentStep.wait($0)] } ?? []
        return AgentRunTests.script([.finalText(taskReply)] + hold + [.finalTextOfLastPrompt])
    }

    /// `true` when `text` is the prompt of ``message`` from the caller.
    ///
    /// - Parameter text: The text of a prompt or a reply.
    /// - Returns: `true` when the text holds the caller prefix and the
    ///   message.
    private static func isCallerMessage(_ text: String) -> Bool {
        text.contains(AgentsToolText.callerMessagePrefix) && text.contains(message)
    }

    /// Makes a run of the reviewer with the idle hooks `hooks`, then begins
    /// its answers.
    ///
    /// - Parameters:
    ///   - harness: The harness of the run.
    ///   - hooks: The idle hooks of the run.
    /// - Returns: The run, when its answers began.
    /// - Throws: The error of `#require` when the registry has no reviewer.
    private static func startRun(in harness: AgentRunHarness, hooks: AgentRunIdleHooks) async throws -> AgentRun {
        let request = try harness.request(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        let run = await harness.makeRun(request)
        run.install(hooks)
        run.begin(request, environment: harness.environment)
        return run
    }

    /// Reads the phase of `run` until the run waits for its children.
    ///
    /// - Parameter run: A run that started a child.
    /// - Throws: `CancellationError` when the test is cancelled.
    private static func waitForChildren(of run: AgentRun) async throws {
        while run.phase != .waitingForChildren {
            try await Task.sleep(for: NestedRunTests.pollInterval)
        }
    }

    /// Reads the answers of `run` until the run read the start of an answer.
    /// The run reads its session events in order, thus the run is then past
    /// each check of the events before that start.
    ///
    /// - Parameter run: A run whose session started an answer.
    /// - Throws: `CancellationError` when the test is cancelled.
    private static func waitForOpenAnswer(of run: AgentRun) async throws {
        while !run.answers.isAnswerOpen {
            try await Task.sleep(for: NestedRunTests.pollInterval)
        }
    }

    /// `true` when `state` is ``AgentRunState/failed(_:)``.
    ///
    /// - Parameter state: The state of a run.
    /// - Returns: `true` for a failure.
    private static func isFailure(_ state: AgentRunState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    @Test("a message in the task turn is delivered, and the run answers it before it ends",
        .timeLimit(.minutes(1)))
    func deliveredInTaskTurn() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.wait(gate), .finalText(Self.taskReply), .finalTextOfLastPrompt]))
        defer { try? harness.delete() }

        let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        await gate.waitForArrival()
        let outcome = await run.deliver(Self.message)
        gate.open()
        let result = try await run.result()

        #expect(outcome == .delivered)
        #expect(harness.script.prompts.contains(where: Self.isCallerMessage))
        #expect(Self.isCallerMessage(result))
    }

    /// The child is the reviewer: it runs on its own model, thus its held
    /// answer does not hold the answer of the parent to the message.
    @Test("a message to a run that waits for its children is delivered and answered",
        .timeLimit(.minutes(1)))
    func deliveredWhileWaitingForChildren() async throws {
        let childGate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: NestedRunTests.leadKey,
                    steps: [
                        NestedRunTests.startStep(NestedRunTests.reviewer, prompt: NestedRunTests.reviewerKey),
                        .finalText(NestedRunTests.startedText),
                        .finalTextOfLastPrompt,
                        .finalTextOfLastPrompt
                    ]),
                ScriptedAgentPlay(
                    key: NestedRunTests.reviewerKey,
                    steps: [.wait(childGate), .finalText(NestedRunTests.reviewerText)])
            ]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let lead = try await runner.start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
        try await Self.waitForChildren(of: lead)
        let outcome = await lead.deliver(Self.message)
        try await NestedRunTests.arrival(ofPromptContaining: Self.message, in: harness.script)
        childGate.open()
        let result = try await lead.result()
        let child = try await NestedRunTests.onlyRun(of: runner, caller: lead.id)

        #expect(outcome == .delivered)
        #expect(harness.script.prompts.contains(where: Self.isCallerMessage))
        #expect(result.contains(child.report))
    }

    @Test("a message to a finished run tells the final state", .timeLimit(.minutes(1)))
    func endedAfterFinish() async throws {
        let harness = try await AgentRunHarness.make(script: AgentRunTests.script([.finalText(Self.taskReply)]))
        defer { try? harness.delete() }

        let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        _ = try await run.result()

        #expect(await run.deliver(Self.message) == .ended(.finished(Self.taskReply)))
        #expect(!harness.script.prompts.contains(where: Self.isCallerMessage))
    }

    @Test("a message to a failed run tells the failure", .timeLimit(.minutes(1)))
    func endedAfterFailure() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }

        let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        let final = await run.finalState()

        #expect(Self.isFailure(final))
        #expect(await run.deliver(Self.message) == .ended(final))
    }

    @Test("a message to a cancelled run tells that it was cancelled", .timeLimit(.minutes(1)))
    func endedAfterCancel() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(script: AgentRunTests.script([.wait(gate)]))
        defer { try? harness.delete() }

        let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        await gate.waitForArrival()
        run.cancel()
        let final = await run.finalState()

        #expect(final == .cancelled)
        #expect(await run.deliver(Self.message) == .ended(.cancelled))
    }

    @Test("a message after a cancel request, before the run settles, tells that it was cancelled",
        .timeLimit(.minutes(1)))
    func endedAfterCancelRequest() async throws {
        let harness = try await AgentRunHarness.make(script: AgentRunTests.script([.finalText(Self.taskReply)]))
        defer { try? harness.delete() }
        let request = try harness.request(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)

        let run = await harness.makeRun(request)
        run.cancel()
        let outcome = await run.deliver(Self.message)
        run.begin(request, environment: harness.environment)
        let final = await run.finalState()

        #expect(outcome == .ended(.cancelled))
        #expect(final == .cancelled)
        #expect(harness.script.prompts.isEmpty)
    }

    @Test("a message to a run whose setup failed tells the failure of the setup")
    func endedAfterSetupFailure() async throws {
        let harness = try await AgentRunHarness.make(script: AgentRunTests.script([.finalText(Self.taskReply)]))
        defer { try? harness.delete() }
        try Data(Self.invalidUTF8).write(
            to: harness.workingDirectory.appendingPathComponent(AgentRunHarness.agentsMdName))

        let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)

        #expect(run.isSetupFailure)
        #expect(await run.deliver(Self.message) == .ended(run.state))
    }

    @Test("a message between the idle signal and the settle of the run is answered before the run ends",
        .timeLimit(.minutes(1)))
    func messageBetweenIdleSignalAndSettleIsAnswered() async throws {
        let settleGate = ScriptedGate()
        let harness = try await AgentRunHarness.make(script: Self.taskThenMessage())
        defer { try? harness.delete() }

        let run = try await Self.startRun(
            in: harness, hooks: AgentRunIdleHooks(beforeIdleSettle: { try? await settleGate.wait() }))
        await settleGate.waitForArrival()
        let outcome = await run.deliver(Self.message)
        settleGate.open()
        let result = try await run.result()

        #expect(outcome == .delivered)
        #expect(Self.isCallerMessage(result))
    }

    @Test("a message that the pump took, before the run read the start of its answer, keeps the run alive",
        .timeLimit(.minutes(1)))
    func messageThatThePumpTookKeepsTheRunAlive() async throws {
        let checkGate = ScriptedGate()
        let messageGate = ScriptedGate()
        let harness = try await AgentRunHarness.make(script: Self.taskThenMessage(holdingMessageAt: messageGate))
        defer { try? harness.delete() }

        let run = try await Self.startRun(
            in: harness, hooks: AgentRunIdleHooks(beforeIdleCheck: { try? await checkGate.wait() }))
        await checkGate.waitForArrival()
        let outcome = await run.deliver(Self.message)
        await messageGate.waitForArrival()
        checkGate.open()
        try await Self.waitForOpenAnswer(of: run)
        messageGate.open()
        let result = try await run.result()

        #expect(outcome == .delivered)
        #expect(Self.isCallerMessage(result))
    }
}
