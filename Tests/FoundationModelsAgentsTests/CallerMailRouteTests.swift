import Foundation
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing
import ULID

/// Pins the mail route of a caller link: a message to a caller that has no
/// live `start agent` call goes to the caller session as mail. A restored
/// child has such a caller link (it comes from the session id alone).
///
/// The runner finds the caller in this order: a run that it holds, then the
/// host mail closure of the environment (``AgentEnvironment/callerMail``).
@Suite("The mail route to a caller")
struct CallerMailRouteTests {
    /// One call of the host mail closure.
    private struct HostMail: Sendable, Equatable {
        /// The text of the message.
        let message: String

        /// The session that sent the message.
        let sender: ULID

        /// The session that gets the message.
        let caller: ULID
    }

    /// The message that each test sends.
    private static let message = "caller-mail-key: the parser has a second entry point"

    /// The reply of the task answer of the held run.
    private static let taskReply = "I reviewed the diff."

    @Test("a caller that the runner does not hold gets the message from the host mail closure")
    func hostCallerGetsTheMessage() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let record = CallRecord<HostMail>()
        let runner = harness.makeRunner(callerMail: { message, sender, caller in
            record.add(HostMail(message: message, sender: sender, caller: caller))
            return MailID()
        })
        let sender = ULID()
        let caller = ULID()

        _ = await runner.mailCaller(Self.message, from: sender, to: caller)

        #expect(record.all == [HostMail(message: Self.message, sender: sender, caller: caller)])
    }

    @Test("the runner tells that the host mail closure delivered the message")
    func hostMailResultIsReturned() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let id = MailID()
        let runner = harness.makeRunner(callerMail: { _, _, _ in id })

        let posted = await runner.mailCaller(Self.message, from: ULID(), to: ULID())

        #expect(posted == id)
    }

    @Test("a caller that the runner does not hold, with no host mail closure, gets no message")
    func unknownCallerWithNoClosureIsNotDelivered() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let posted = await runner.mailCaller(Self.message, from: ULID(), to: ULID())

        #expect(posted == nil)
    }

    @Test("a caller that is a run of the runner gets the message as mail, and answers it")
    func runCallerGetsTheMessage() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([.wait(gate), .finalText(Self.taskReply), .finalTextOfLastPrompt]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()
        let caller = try await runner.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        try #require(await gate.waitForArrival(orEndOf: caller))

        let posted = await runner.mailCaller(Self.message, from: ULID(), to: caller.id)
        gate.open()
        _ = try await caller.result()

        #expect(posted != nil)
        #expect(harness.script.prompts.contains(where: { $0.contains(Self.message) }))
    }

    // MARK: - The mail route of a caller link

    /// Makes the context of a tool whose caller link has the mail route.
    ///
    /// - Parameters:
    ///   - runner: The runner of the tool.
    ///   - caller: The session id of the caller.
    /// - Returns: The context, with the messaging grant.
    private static func mailRouteContext(runner: AgentRunner, caller: ULID) -> AgentsToolContext {
        AgentsToolContext(
            runner: runner, allowedNames: nil, parent: nil,
            callerLink: AgentsToolContext.CallerLink(sessionID: caller, route: .mail), grant: .messagingOnly)
    }

    @Test("send caller on the mail route sends the message as mail to the caller session")
    func mailRouteSendsMail() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let record = CallRecord<HostMail>()
        let runner = harness.makeRunner(callerMail: { message, sender, caller in
            record.add(HostMail(message: message, sender: sender, caller: caller))
            return MailID()
        })
        let sender = ULID()
        let caller = ULID()

        _ = await Self.mailRouteContext(runner: runner, caller: caller).messageCaller(Self.message, from: sender)

        #expect(record.all == [HostMail(message: Self.message, sender: sender, caller: caller)])
    }

    @Test("send caller on the mail route answers that the message was sent")
    func mailRouteAnswersSent() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner(callerMail: { _, _, _ in MailID() })

        let answer = await Self.mailRouteContext(runner: runner, caller: ULID())
            .messageCaller(Self.message, from: ULID())

        #expect(answer == .success(AgentsToolText.messageSentToCaller))
    }

    @Test("send caller on the mail route tells when the caller cannot get the message")
    func mailRouteCorrectsWhenNotDelivered() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let answer = await Self.mailRouteContext(runner: runner, caller: ULID())
            .messageCaller(Self.message, from: ULID())

        #expect(answer == .corrective(AgentsToolText.callerNotReachable))
    }
}
