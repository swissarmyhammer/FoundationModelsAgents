import Foundation
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing
import ULID

/// Pins the nested runs (plan.md §8 steps 7 and 8, §8.2, §9.3, §16): a run
/// with the `agents` tool starts children, reads their final messages in
/// delivery turns, and finishes only after them. A cancel or a failure of the
/// parent cancels its open children, waits for them, and then posts.
///
/// The root sessions and the `lead` runs are on the `standard` slot. A gated
/// child is code-reviewer on the `flash` slot, thus the gated turn does not
/// hold the generation gate of the parent.
@Suite("Nested runs")
struct NestedRunTests {
    /// A failure that a scripted step throws.
    enum ScriptedFailure: Error {
        /// The model call of the step failed.
        case broken
    }

    /// The agent of the fixture library that starts code-reviewer and
    /// test-writer.
    static let lead = "lead"

    /// The agent of the fixture library on the `flash` slot.
    static let reviewer = AgentRunTests.reviewer

    /// The agent of the fixture library on the `standard` slot.
    static let testWriter = AgentRunTests.testWriter

    /// The key of the play of the root session. It is its instructions.
    static let rootKey = "nested-root-play-key"

    /// The first prompt of each root session.
    static let rootPrompt = "Give the work to an agent."

    /// The answer of the turn of a root session.
    static let rootText = "I started an agent."

    /// The answer of the task turn of each parent run.
    static let startedText = "I started the agents."

    /// The key of the play of the lead run.
    static let leadKey = "nested-lead-key: divide the task"

    /// The key of the play of the code-reviewer child.
    static let reviewerKey = "nested-reviewer-key: review the parser"

    /// The key of the play of the test-writer child.
    static let testWriterKey = "nested-test-writer-key: test the parser"

    /// The final text of the code-reviewer child.
    static let reviewerText = "The parser is correct."

    /// The final text of the test-writer child.
    static let testWriterText = "The tests of the parser pass."

    /// The answer of the second turn of the root session in the dispatch
    /// test.
    private static let deliveredText = "The reviewer finished."

    /// The sentence that `check agent` adds for a run that waits for one
    /// child.
    private static let waitingForOneText = "It waits for 1 agents that it started."

    /// The time between two reads of the report of a run.
    private static let pollInterval = Duration.milliseconds(10)

    /// A scripted call of `start agent`.
    ///
    /// - Parameters:
    ///   - name: The name of the agent.
    ///   - prompt: The prompt of the run. It is the key of its play.
    /// - Returns: The step.
    static func startStep(_ name: String, prompt: String) -> ScriptedAgentStep {
        .toolCall(
            name: ToolVocabulary.agentsToolName,
            argumentsJSON: #"{"op": "start agent", "name": "\#(name)", "prompt": "\#(prompt)"}"#)
    }

    /// The play of a parent run: it starts one run for each entry of
    /// `children` in its task turn, answers ``startedText``, then answers
    /// each delivery turn with the prompts that it read.
    ///
    /// - Parameters:
    ///   - key: The key of the play.
    ///   - children: The name and the prompt of each child.
    /// - Returns: The play.
    static func parentPlay(_ key: String, children: [(name: String, prompt: String)]) -> ScriptedAgentPlay {
        let starts = children.map { child in startStep(child.name, prompt: child.prompt) }
        let deliveries = [ScriptedAgentStep](repeating: .finalTextOfLaterPrompts, count: children.count)
        return ScriptedAgentPlay(key: key, steps: starts + [.finalText(startedText)] + deliveries)
    }

    /// The play of the root session: it starts one run, then answers.
    ///
    /// - Parameters:
    ///   - name: The name of the agent to start.
    ///   - prompt: The prompt of the run.
    /// - Returns: The play.
    static func rootPlay(starting name: String, prompt: String) -> ScriptedAgentPlay {
        ScriptedAgentPlay(key: rootKey, steps: [startStep(name, prompt: prompt), .finalText(rootText)])
    }

    /// Makes a root session over the `standard` slot, with the `agents` tool
    /// of the harness.
    ///
    /// - Parameter harness: The harness of the tool.
    /// - Returns: The root session.
    static func rootSession(of harness: AgentsToolHarness) -> any RoutedSession {
        harness.runHarness.profile.standard.makeSession(instructions: rootKey, tools: [harness.tool])
    }

    /// Gives the one run that `caller` started.
    ///
    /// - Parameters:
    ///   - runner: The runner of the runs.
    ///   - caller: The id of the session of the caller.
    /// - Returns: The run.
    /// - Throws: The error of `#require` when the caller started no run.
    static func onlyRun(of runner: AgentRunner, caller: ULID) async throws -> AgentRun {
        let runs = await runner.runs(caller: caller)
        #expect(runs.count == 1)
        return try #require(runs.first)
    }

    /// Gives the `.completed` events that the transcript in `directory`
    /// journaled for the tool call that started `run`.
    ///
    /// - Parameters:
    ///   - run: The run that posted.
    ///   - directory: The recording directory of the session of the caller.
    /// - Returns: The events, in file order.
    /// - Throws: The error of `#require` when the run has no context, or the
    ///   error of the read.
    static func posts(of run: AgentRun, in directory: URL?) throws -> [OperationEvent] {
        let token = try #require(run.context?.completionToken)
        return try RecordedTranscript.operationEvents(in: try #require(directory))
            .filter { $0.kind == .completed && $0.correlationID == token }
    }

    /// `true` when `state` failed with ``AgentRunFailure/modelFailed(_:)``.
    ///
    /// - Parameter state: The state of a run.
    /// - Returns: `true` for that failure.
    private static func isModelFailure(_ state: AgentRunState) -> Bool {
        if case .failed(.modelFailed) = state { return true }
        return false
    }

    /// Reads the report of `run` until it ends with the waiting sentence
    /// for one child.
    ///
    /// - Parameter run: A run that waits for one child after its task turn.
    /// - Returns: The report.
    /// - Throws: `CancellationError` when the test is cancelled.
    private static func waitingReport(of run: AgentRun) async throws -> String {
        while !run.report.hasSuffix(waitingForOneText) {
            try await Task.sleep(for: pollInterval)
        }
        return run.report
    }

    @Test("a lead starts two children, reads both posts in delivery turns, and its final text holds both results",
        .timeLimit(.minutes(1)))
    func leadJoinsBothResults() async throws {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                Self.parentPlay(
                    Self.leadKey,
                    children: [(Self.reviewer, Self.reviewerKey), (Self.testWriter, Self.testWriterKey)]),
                ScriptedAgentPlay(key: Self.reviewerKey, steps: [.finalText(Self.reviewerText)]),
                ScriptedAgentPlay(key: Self.testWriterKey, steps: [.finalText(Self.testWriterText)])
            ]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let lead = try await runner.start(Self.lead, prompt: Self.leadKey)
        let result = try await lead.result()
        let children = await runner.runs(caller: lead.id)
        let prompts = harness.script.prompts

        #expect(result.contains(Self.reviewerText))
        #expect(result.contains(Self.testWriterText))
        #expect(children.map(\.agent.id).sorted() == [Self.reviewer, Self.testWriter])
        #expect(children.allSatisfy { $0.depth == AgentRunner.hostDepth + 1 })
        #expect(prompts.filter { $0.contains(Self.reviewerText) }.count == 1)
        #expect(prompts.filter { $0.contains(Self.testWriterText) }.count == 1)
    }

    @Test("the parent finishes only after its child, and check agent tells that it waits",
        .timeLimit(.minutes(1)))
    func parentFinishesAfterChild() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                Self.parentPlay(Self.leadKey, children: [(Self.reviewer, Self.reviewerKey)]),
                ScriptedAgentPlay(key: Self.reviewerKey, steps: [.wait(gate), .finalText(Self.reviewerText)])
            ]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let lead = try await runner.start(Self.lead, prompt: Self.leadKey)
        await gate.waitForArrival()
        let report = try await Self.waitingReport(of: lead)
        let stateWhileWaiting = lead.state
        let child = try await Self.onlyRun(of: runner, caller: lead.id)
        gate.open()
        let result = try await lead.result()

        #expect(report.hasPrefix("\(lead.subject) is running: "))
        #expect(stateWhileWaiting == .running)
        #expect(child.state == .finished(Self.reviewerText))
        #expect(result.contains(Self.reviewerText))
    }

    @Test("a failing parent cancels its open child first, then posts", .timeLimit(.minutes(1)))
    func failingParentCancelsChildThenPosts() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(
            script: ScriptedAgentScript([
                Self.rootPlay(starting: Self.lead, prompt: Self.leadKey),
                ScriptedAgentPlay(
                    key: Self.leadKey,
                    steps: [Self.startStep(Self.reviewer, prompt: Self.reviewerKey), .fail(ScriptedFailure.broken)]),
                ScriptedAgentPlay(key: Self.reviewerKey, steps: [.wait(gate), .finalText(Self.reviewerText)])
            ]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        let lead = try await Self.onlyRun(of: harness.runner, caller: root.id)
        let leadFinal = await lead.finalState()
        let child = try await Self.onlyRun(of: harness.runner, caller: lead.id)
        let childStateAtParentEnd = child.state
        let leadPosts = try Self.posts(of: lead, in: root.recordingDirectory)
        let childPosts = try Self.posts(of: child, in: lead.recordingDirectory)
        await root.close()

        #expect(Self.isModelFailure(leadFinal))
        #expect(childStateAtParentEnd == .cancelled)
        #expect(childPosts.map(\.outcome) == [.cancelled])
        #expect(leadPosts.map(\.outcome) == [.failed])
    }

    @Test("cancel() on a parent with an open child cancels the child and waits for it before it posts",
        .timeLimit(.minutes(1)))
    func cancelledParentCancelsChildThenPosts() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentsToolHarness.make(
            script: ScriptedAgentScript([
                Self.rootPlay(starting: Self.lead, prompt: Self.leadKey),
                Self.parentPlay(Self.leadKey, children: [(Self.reviewer, Self.reviewerKey)]),
                ScriptedAgentPlay(key: Self.reviewerKey, steps: [.wait(gate), .finalText(Self.reviewerText)])
            ]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        await gate.waitForArrival()
        let lead = try await Self.onlyRun(of: harness.runner, caller: root.id)
        let child = try await Self.onlyRun(of: harness.runner, caller: lead.id)
        lead.cancel()
        let leadFinal = await lead.finalState()
        let childStateAtParentEnd = child.state
        let leadPosts = try Self.posts(of: lead, in: root.recordingDirectory)
        let childPosts = try Self.posts(of: child, in: lead.recordingDirectory)
        await root.close()

        #expect(leadFinal == .cancelled)
        #expect(childStateAtParentEnd == .cancelled)
        #expect(childPosts.map(\.outcome) == [.cancelled])
        #expect(leadPosts.map(\.detail) == ["\(lead.subject) was cancelled."])
    }

    @Test("dispatchNextPrompt() with a staged .completed runs one turn; with nothing staged it gives nil",
        .timeLimit(.minutes(1)))
    func dispatchRunsOneTurnThenGivesNil() async throws {
        let harness = try await AgentsToolHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: Self.rootKey,
                    steps: [
                        Self.startStep(Self.reviewer, prompt: Self.reviewerKey),
                        .finalText(Self.rootText),
                        .finalText(Self.deliveredText)
                    ]),
                ScriptedAgentPlay(key: Self.reviewerKey, steps: [.finalText(Self.reviewerText)])
            ]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        let child = try await Self.onlyRun(of: harness.runner, caller: root.id)
        _ = try await child.result()
        let delivered = try await root.dispatchNextPrompt()
        let deliveryPrompt = harness.runHarness.script.prompts.last
        let nothing = try await root.dispatchNextPrompt()
        await root.close()

        #expect(delivered == Self.deliveredText)
        #expect(deliveryPrompt?.contains(Self.reviewerText) == true)
        #expect(nothing == nil)
    }

    @Test("agentSpawn links three sessions, and parentToolCallId is the completion token of start agent",
        .timeLimit(.minutes(1)))
    func agentSpawnLinksThreeSessions() async throws {
        let harness = try await AgentsToolHarness.make(
            script: ScriptedAgentScript([
                Self.rootPlay(starting: Self.lead, prompt: Self.leadKey),
                Self.parentPlay(Self.leadKey, children: [(Self.reviewer, Self.reviewerKey)]),
                ScriptedAgentPlay(key: Self.reviewerKey, steps: [.finalText(Self.reviewerText)])
            ]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        let lead = try await Self.onlyRun(of: harness.runner, caller: root.id)
        _ = try await lead.result()
        let child = try await Self.onlyRun(of: harness.runner, caller: lead.id)
        let leadToken = try #require(lead.context?.completionToken)
        let childToken = try #require(child.context?.completionToken)
        let rootSpawn = try RecordedSidecar.read(in: root.recordingDirectory).agentSpawn
        let leadSpawn = try AgentRunTests.sidecar(of: lead).agentSpawn
        let childSpawn = try AgentRunTests.sidecar(of: child).agentSpawn
        let leadPosts = try Self.posts(of: lead, in: root.recordingDirectory)
        await root.close()

        #expect(rootSpawn == nil)
        #expect(leadSpawn == SessionSidecar.AgentSpawn(parentSessionId: root.id, parentToolCallId: leadToken))
        #expect(childSpawn == SessionSidecar.AgentSpawn(parentSessionId: lead.id, parentToolCallId: childToken))
        #expect(leadPosts.map(\.correlationID) == [leadToken])
    }
}
