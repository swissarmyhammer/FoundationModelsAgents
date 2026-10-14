@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Synchronization
import Testing

/// Pins the queue part of the idle rule of a run: only user-type mail in the
/// queue keeps the session of a run from idle. Run mail that waits in the
/// queue does not.
///
/// The order of each step is fixed. The tool of the run posts its progress
/// event in the last answer of the run, and then holds on a gate. Thus the
/// progress mail is in the queue before that answer ends, and progress mail
/// starts no submission. The test reads the queue while the tool holds. The
/// `beforeIdleCheck` hook of the run reads the queue at the idle check after
/// the answer. The test uses no clock and no poll.
@Suite("The idle rule of a run")
struct AgentRunIdleRuleTests {
    /// The queue depths that the `beforeIdleCheck` hook of a run read, in
    /// the order of the idle checks.
    ///
    /// A class, because the hook and the test share it. A `Mutex` guards the
    /// depths, thus the `Sendable` conformance is compiler-checked.
    private final class IdleCheckDepths: Sendable {
        /// The depths.
        private let depths = Mutex<[MailQueueDepth]>([])

        /// The depths, in the order of the idle checks.
        var all: [MailQueueDepth] {
            depths.withLock { $0 }
        }

        /// Records the depth of one idle check.
        ///
        /// - Parameter depth: The depth that the check read.
        func record(_ depth: MailQueueDepth) {
            depths.withLock { $0.append(depth) }
        }
    }

    /// The name of the tool that the run calls. The fixture agent
    /// code-reviewer lists it in its `tools` key.
    private static let toolName = "Read"

    /// The detail of the progress event that the tool posts.
    private static let progressDetail = "idle-rule-progress: half of the files are read"

    /// The output of the tool.
    private static let toolOutput = "idle-rule-output: the files are read"

    /// The reply of the last answer of the run.
    private static let reply = "idle-rule-reply: the diff is correct."

    /// The kinds of user-type mail.
    private static let userTypeKinds: [MailKind] = [.userMessage, .agentMessage, .elicitationAnswer]

    @Test("progress run mail that waits in the queue after the last answer does not keep the run from idle")
    func waitingProgressMailDoesNotKeepTheRunFromIdle() async throws {
        let toolGate = ScriptedGate()
        var tools = ToolCatalog()
        tools.register(Self.toolName) {
            ProgressPostingTool(
                name: Self.toolName, progressDetail: Self.progressDetail, output: Self.toolOutput, gate: toolGate)
        }
        let harness = try await AgentRunHarness.make(
            script: AgentRunTests.script([
                .toolCall(name: Self.toolName, argumentsJSON: #"{"text": "parser.swift"}"#),
                .finalText(Self.reply)
            ]),
            tools: tools)
        defer { try? harness.delete() }
        let request = try harness.request(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
        let run = await harness.makeRun(request)
        let idleChecks = IdleCheckDepths()
        run.install(
            AgentRunIdleHooks(beforeIdleCheck: { [run, idleChecks] in
                guard let session = run.heldSession else {
                    return
                }
                idleChecks.record(await session.mailQueueDepth())
            }))

        run.begin(request, environment: harness.environment)
        await toolGate.waitForArrival()
        let session = try #require(run.heldSession)
        let depthInAnswer = await session.mailQueueDepth()
        toolGate.open()
        let result = try await run.result()
        let depthAtIdle = try #require(idleChecks.all.last)

        #expect(depthInAnswer.depthByKind[.runEvent] == 1)
        #expect(!depthInAnswer.running.isEmpty)
        #expect(result == Self.reply)
        #expect(run.state == .finished(Self.reply))
        #expect((depthAtIdle.depthByKind[.runEvent] ?? 0) > 0)
        #expect(Self.userTypeKinds.allSatisfy { depthAtIdle.depthByKind[$0] == nil })
        #expect(depthAtIdle.running.isEmpty)
    }
}
