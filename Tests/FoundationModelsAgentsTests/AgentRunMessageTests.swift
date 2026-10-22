import Foundation
import FoundationModels
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Synchronization
import Testing
import ULID

/// Pins ``AgentRun/deliver(_:from:)``: a caller sends a message to a run that
/// it started. The run accepts the message and answers it before it ends, or
/// it tells that it ended. A message never races with the idle rule of the
/// run.
///
/// Most tests send as `MailSender.user`, a host that is not a session: the
/// prompt of the message then holds the caller prefix
/// (``AgentsToolText/callerMessage(_:)``). The tests of a session sender pin
/// the fenced prompt of the Router (``RouterAgentMessage``).
@Suite("Messages to a run")
struct AgentRunMessageTests {
    /// The session events of one run that the run event observer got: the
    /// ids of the delivered mail, in delivery order, and the mail ids of each
    /// answer, in answer order.
    ///
    /// A class, because the observer and the test share it. A `Mutex` guards
    /// the state, thus the `Sendable` conformance is compiler-checked.
    private final class MailLedger: Sendable {
        /// The state that the lock guards.
        private struct State {
            /// The id of each delivered mail, in delivery order.
            var delivered: [MailID] = []

            /// The mail ids of each answer, in answer order.
            var answered: [[MailID]] = []
        }

        /// The state.
        private let state = Mutex(State())

        /// The id of each delivered mail, in delivery order.
        var delivered: [MailID] {
            state.withLock { $0.delivered }
        }

        /// The mail ids of each answer, in answer order.
        var answered: [[MailID]] {
            state.withLock { $0.answered }
        }

        /// Records one session event.
        ///
        /// - Parameter event: The event.
        func observe(_ event: SessionEvent) {
            state.withLock { state in
                if case .mailDelivered(let id) = event {
                    state.delivered.append(id)
                }
                if case .answered(let answer) = event {
                    state.answered.append(answer.mailIds)
                }
            }
        }
    }

    /// The count of the `submissionStarted` events of one run that the run
    /// event observer got.
    ///
    /// A class, because the observer and the test share it. A `Mutex` guards
    /// the count, thus the `Sendable` conformance is compiler-checked.
    private final class SubmissionStartCount: Sendable {
        /// The count.
        private let count = Mutex(0)

        /// Adds one start.
        ///
        /// - Returns: The count after this start.
        func increment() -> Int {
            count.withLock { count in
                count += 1
                return count
            }
        }
    }

    /// The number of the submission start of the answer to the message: the
    /// task answer has the first start.
    private static let messageAnswerStart = 2

    /// The message that each test sends to a run.
    private static let message = "message-key: also check the error paths"

    /// The reply of the answer of the task prompt.
    private static let taskReply = "I reviewed the diff."

    /// The session that sends the message in the tests of a session sender.
    private static let senderSession = ULID()

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

    /// `true` when `text` is the prompt of ``message`` from a user sender.
    ///
    /// - Parameter text: The text of a prompt or a reply.
    /// - Returns: `true` when the text holds the caller prefix and the
    ///   message.
    private static func isCallerMessage(_ text: String) -> Bool {
        text.contains("Message from your caller: \(message)")
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

    /// `true` when `state` is ``AgentRunState/failed(_:)``.
    ///
    /// - Parameter state: The state of a run.
    /// - Returns: `true` for a failure.
    private static func isFailure(_ state: AgentRunState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    @Test("a message in the task turn is delivered, and the run answers it before it ends")
    func deliveredInTaskTurn() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.wait(gate), .finalText(Self.taskReply), .finalTextOfLastPrompt]))
        defer { try? harness.delete() }

        let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        try #require(await gate.waitForArrival(orEndOf: run))
        let outcome = try run.deliver(Self.message, from: .user)
        gate.open()
        let result = try await run.result()

        #expect(outcome == .delivered)
        #expect(harness.script.prompts.contains(where: Self.isCallerMessage))
        #expect(Self.isCallerMessage(result))
    }

    /// The child is the reviewer: it runs on its own model, thus its held
    /// answer does not hold the answer of the parent to the message.
    ///
    /// The run event observer opens a gate at the `answered` event of the
    /// task answer of the lead. The test delivers the message after that
    /// event, thus after the task answer ended and while the child holds.
    /// The end of the lead also opens the gate, thus a lead that fails
    /// before that event does not hold the test.
    @Test("a message to a run that waits for its children is delivered and answered")
    func deliveredWhileWaitingForChildren() async throws {
        let childGate = ScriptedGate()
        let taskAnswered = ScriptedGate()
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
            ]),
            runEventObserver: { run, output in
                if run.agent.id == NestedRunTests.lead, case .answered = output.event {
                    taskAnswered.open()
                }
            })
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let lead = try await runner.start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
        try await taskAnswered.wait(orEndOf: lead)
        let outcome = try lead.deliver(Self.message, from: .user)
        try #require(outcome == .delivered)
        try await NestedRunTests.arrival(ofPromptContaining: Self.message, in: harness.script)
        childGate.open()
        let result = try await lead.result()
        let child = try await NestedRunTests.onlyRun(of: runner, caller: lead.id)

        #expect(harness.script.prompts.contains(where: Self.isCallerMessage))
        #expect(result.contains(child.report))
    }

    @Test("a message to a finished run tells the final state")
    func endedAfterFinish() async throws {
        let harness = try await AgentRunHarness.make(script: AgentRunTests.script([.finalText(Self.taskReply)]))
        defer { try? harness.delete() }

        let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        _ = try await run.result()

        #expect(try run.deliver(Self.message, from: .user) == .ended(.finished(Self.taskReply)))
        #expect(!harness.script.prompts.contains(where: Self.isCallerMessage))
    }

    @Test("a message to a failed run tells the failure")
    func endedAfterFailure() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }

        let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        let final = await run.finalState()

        #expect(Self.isFailure(final))
        #expect(try run.deliver(Self.message, from: .user) == .ended(final))
    }

    @Test("a message to a cancelled run tells that it was cancelled")
    func endedAfterCancel() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(script: AgentRunTests.script([.wait(gate)]))
        defer { try? harness.delete() }

        let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        try #require(await gate.waitForArrival(orEndOf: run))
        run.cancel()
        let final = await run.finalState()

        #expect(final == .cancelled)
        #expect(try run.deliver(Self.message, from: .user) == .ended(.cancelled))
    }

    @Test("a message after a cancel request, before the run settles, tells that it was cancelled")
    func endedAfterCancelRequest() async throws {
        let harness = try await AgentRunHarness.make(script: AgentRunTests.script([.finalText(Self.taskReply)]))
        defer { try? harness.delete() }
        let request = try harness.request(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)

        let run = await harness.makeRun(request)
        run.cancel()
        let outcome = try run.deliver(Self.message, from: .user)
        run.begin(request, environment: harness.environment)
        let final = await run.finalState()

        #expect(outcome == AgentRunMessageOutcome.ended(.cancelled))
        #expect(final == .cancelled)
        #expect(harness.script.prompts.isEmpty)
    }

    @Test("a message before begin is held, and the session gets it after the task prompt")
    func messageBeforeBeginComesAfterTaskPrompt() async throws {
        let harness = try await AgentRunHarness.make(script: Self.taskThenMessage())
        defer { try? harness.delete() }
        let request = try harness.request(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)

        let run = await harness.makeRun(request)
        let outcome = try run.deliver(Self.message, from: .user)
        run.begin(request, environment: harness.environment)
        let result = try await run.result()
        let prompts = harness.script.prompts

        #expect(outcome == .delivered)
        let firstPrompt = try #require(prompts.first)
        #expect(firstPrompt.contains(AgentRunTests.prompt))
        #expect(!Self.isCallerMessage(firstPrompt))
        #expect(prompts.dropFirst().contains(where: Self.isCallerMessage))
        #expect(Self.isCallerMessage(result))
    }

    /// `begin` starts the task that mails the task prompt, and returns before
    /// that task mails it. The run holds the message until the task prompt
    /// is in the mail queue, thus the result does not depend on the time of
    /// that mail.
    @Test("a message right after begin is held, and the session gets it after the task prompt")
    func messageRightAfterBeginComesAfterTaskPrompt() async throws {
        let harness = try await AgentRunHarness.make(script: Self.taskThenMessage())
        defer { try? harness.delete() }

        let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        let outcome = try run.deliver(Self.message, from: .user)
        let result = try await run.result()
        let prompts = harness.script.prompts

        #expect(outcome == .delivered)
        let firstPrompt = try #require(prompts.first)
        #expect(firstPrompt.contains(AgentRunTests.prompt))
        #expect(!Self.isCallerMessage(firstPrompt))
        #expect(Self.isCallerMessage(result))
    }

    @Test("a message to a run whose setup failed tells the failure of the setup")
    func endedAfterSetupFailure() async throws {
        let harness = try await AgentRunHarness.make(script: AgentRunTests.script([.finalText(Self.taskReply)]))
        defer { try? harness.delete() }
        try Data(Self.invalidUTF8).write(
            to: harness.workingDirectory.appendingPathComponent(AgentRunHarness.agentsMdName))

        let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)

        #expect(run.isSetupFailure)
        #expect(try run.deliver(Self.message, from: .user) == .ended(run.state))
    }

    @Test("a message between the idle signal and the settle of the run is answered before the run ends")
    func messageBetweenIdleSignalAndSettleIsAnswered() async throws {
        let settleGate = ScriptedGate()
        let harness = try await AgentRunHarness.make(script: Self.taskThenMessage())
        defer { try? harness.delete() }

        let run = try await Self.startRun(
            in: harness, hooks: AgentRunIdleHooks(beforeIdleSettle: { try? await settleGate.wait() }))
        try #require(await settleGate.waitForArrival(orEndOf: run))
        let outcome = try run.deliver(Self.message, from: .user)
        settleGate.open()
        let result = try await run.result()

        #expect(outcome == .delivered)
        #expect(Self.isCallerMessage(result))
    }

    @Test("a message that the pump took, before the run read the start of its answer, keeps the run alive")
    func messageThatThePumpTookKeepsTheRunAlive() async throws {
        let checkGate = ScriptedGate()
        let messageGate = ScriptedGate()
        let messageAnswerRead = ScriptedGate()
        let starts = SubmissionStartCount()
        let harness = try await AgentRunHarness.make(
            script: Self.taskThenMessage(holdingMessageAt: messageGate),
            runEventObserver: { _, output in
                guard case .submissionStarted = output.event else { return }
                // The run calls the observer of an event only after it handled
                // each event before it. Thus at the start of the second answer,
                // the idle check of the task answer is done.
                if starts.increment() == Self.messageAnswerStart {
                    messageAnswerRead.open()
                }
            })
        defer { try? harness.delete() }

        let run = try await Self.startRun(
            in: harness, hooks: AgentRunIdleHooks(beforeIdleCheck: { try? await checkGate.wait() }))
        try #require(await checkGate.waitForArrival(orEndOf: run))
        let outcome = try run.deliver(Self.message, from: .user)
        try #require(outcome == .delivered)
        await messageGate.waitForArrival()
        checkGate.open()
        try await messageAnswerRead.wait()
        messageGate.open()
        let result = try await run.result()

        #expect(Self.isCallerMessage(result))
    }

    /// The order is fixed: the test delivers the message after `make` and
    /// before `begin`, thus before the run mails its task prompt. The run
    /// holds the message, and mails it at once after the task prompt. The run
    /// event observer records the `mailDelivered` events and the mail ids of
    /// each answer. The test finds the two mails by their sender, not by a
    /// search of the text.
    @Test("a message before the task prompt is mailed comes after the task prompt in the queue, and the run answers it")
    func heldMessageIsDeliveredAfterTheTaskPrompt() async throws {
        let ledger = MailLedger()
        let harness = try await AgentRunHarness.make(
            script: Self.taskThenMessage(), runEventObserver: { _, output in ledger.observe(output.event) })
        defer { try? harness.delete() }
        let request = try harness.request(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)

        let run = await harness.makeRun(request)
        let outcome = try run.deliver(Self.message, from: .session(Self.senderSession))
        run.begin(request, environment: harness.environment)
        let result = try await run.result()
        let mailed = run.mailedUserTypeMail
        let taskID = try #require(mailed.first { $0.sender == .user }?.id)
        let messageID = try #require(mailed.first { $0.sender == .session(Self.senderSession) }?.id)
        let delivered = ledger.delivered
        let taskPosition = try #require(delivered.firstIndex(of: taskID))
        let messagePosition = try #require(delivered.firstIndex(of: messageID))

        #expect(outcome == .delivered)
        #expect(mailed.map(\.id) == [taskID, messageID])
        #expect(taskPosition < messagePosition)
        #expect(ledger.answered.contains { $0.contains(messageID) })
        #expect(result == RouterAgentMessage.prompt(Self.message, from: Self.senderSession))
    }

    @Test(
        "a message from a sender that is not a session and not a user throws, and the run mails nothing",
        arguments: [MailSender.run(correlationID: "run-sender-token"), .catalog(.agents)])
    func unsupportedSenderThrowsAndMailsNothing(sender: MailSender) async throws {
        let harness = try await AgentRunHarness.make(script: AgentRunTests.script([.finalText(Self.taskReply)]))
        defer { try? harness.delete() }
        let request = try harness.request(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)

        let run = await harness.makeRun(request)
        #expect(throws: AgentRunMessageError.unsupportedSender(sender)) {
            try run.deliver(Self.message, from: sender)
        }
        run.begin(request, environment: harness.environment)
        let result = try await run.result()

        #expect(result == Self.taskReply)
        #expect(run.mailedUserTypeMail.map(\.sender) == [.user])
        #expect(harness.script.prompts == [AgentRunTests.prompt])
    }

    /// Runs a run whose task answer ends with ``taskReply``, holds the run at
    /// its idle settle, delivers a message, and lets the answer of that
    /// message fail with `error`.
    ///
    /// The order is fixed: the `beforeIdleSettle` hook holds the run after
    /// the idle signal of the task answer. The test delivers the message
    /// while the run holds, thus the idle settle sees a new message and the
    /// run goes on. The second step of the script fails the answer of the
    /// message. The answer of a message from the caller is not an answer to
    /// mail alone, thus only the wait for the id of the message tells the
    /// failure.
    ///
    /// - Parameter error: The error of the answer of the message.
    /// - Returns: The final state of the run.
    /// - Throws: The error of the harness or of `#require`.
    private static func finalStateAfterFailedCallerAnswer(_ error: any Error) async throws -> AgentRunState {
        let settleGate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.finalText(taskReply), .fail(error)]))
        defer { try? harness.delete() }

        let run = try await startRun(
            in: harness, hooks: AgentRunIdleHooks(beforeIdleSettle: { try? await settleGate.wait() }))
        try #require(await settleGate.waitForArrival(orEndOf: run))
        let outcome = try run.deliver(message, from: .user)
        settleGate.open()
        let final = await run.finalState()

        #expect(outcome == .delivered)
        #expect(run.mailedUserTypeMail.count == 2)
        return final
    }

    @Test("a message after the task answer whose answer fails ends the run with the failure of that answer")
    func failedCallerAnswerFailsTheRun() async throws {
        let final = try await Self.finalStateAfterFailedCallerAnswer(NestedRunTests.ScriptedFailure.broken)

        #expect(final == .failed(AgentRunFailure.turnFailure(for: NestedRunTests.ScriptedFailure.broken)))
    }

    @Test("a message after the task answer whose answer overflows the context ends the run with contextOverflow")
    func overflowingCallerAnswerFailsTheRun() async throws {
        let overflow = LanguageModelError.contextSizeExceeded(
            .init(contextSize: 100, tokenCount: 150, debugDescription: "scripted context overflow"))

        let final = try await Self.finalStateAfterFailedCallerAnswer(overflow)

        #expect(final == .failed(AgentRunFailure.turnFailure(for: overflow)))
        if case .failed(.contextOverflow) = final {} else {
            Issue.record("the final state is \(final), not a context overflow")
        }
    }

    @Test("a message from a user is mailed as a user message with the caller prefix")
    func userMessageHoldsTheCallerPrefix() async throws {
        let harness = try await AgentRunHarness.make(script: Self.taskThenMessage())
        defer { try? harness.delete() }
        let request = try harness.request(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)

        let run = await harness.makeRun(request)
        let outcome = try run.deliver(Self.message, from: .user)
        run.begin(request, environment: harness.environment)
        let result = try await run.result()
        let mailed = run.mailedUserTypeMail

        #expect(outcome == .delivered)
        #expect(mailed.count == 2)
        #expect(mailed.last?.sender == .user)
        #expect(
            mailed.last?.body
                == .userMessage(
                    prompt: "Message from your caller: \(Self.message)", options: UserMessageOptions()))
        #expect(result == "Message from your caller: \(Self.message)")
    }
}
