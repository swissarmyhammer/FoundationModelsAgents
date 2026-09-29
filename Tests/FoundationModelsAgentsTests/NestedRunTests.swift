import Foundation
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing
import ULID

/// Pins the nested runs (plan.md §8 steps 7 and 8, §8.2, §9.3, §16): a run
/// with the `agents` tool starts children, the final message of each child
/// comes to it as mail, and it finishes only after it answered them. A cancel
/// or a failure of the parent cancels its open children and waits for them.
///
/// The root sessions and the parent runs are on the `standard` slot.
/// code-reviewer runs on the `flash` slot, and test-writer on the `standard`
/// slot. The Router gives the two slots two different models.
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

    /// The answer of the first answer of a root session.
    static let rootText = "I started an agent."

    /// The answer of the task answer of each parent run.
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

    /// The sentence that `check agent` adds for a run that waits for one
    /// child.
    private static let waitingForOneText = "It waits for 1 agents that it started."

    /// The time between two reads of a value that a test waits for: the
    /// prompts of a script, or the report or the phase of a run.
    static let pollInterval = Duration.milliseconds(10)

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
    /// `children` in its task answer, answers ``startedText``, then answers
    /// each mail with the text of each prompt that it read after its task
    /// prompt.
    ///
    /// The steps after ``startedText`` are all the same. Thus the play is
    /// correct also when one mail holds the final messages of two children.
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

    /// Waits until the model got a prompt that contains `text`.
    ///
    /// - Parameters:
    ///   - text: The text of the prompt.
    ///   - script: The script that records the prompts.
    /// - Throws: `CancellationError` when the test is cancelled.
    static func arrival(ofPromptContaining text: String, in script: ScriptedAgentScript) async throws {
        while !script.prompts.contains(where: { $0.contains(text) }) {
            try await Task.sleep(for: pollInterval)
        }
    }

    /// The play of the root session: it starts one run, answers, then
    /// answers the mail of the run with the mail.
    ///
    /// - Parameters:
    ///   - name: The name of the agent to start.
    ///   - prompt: The prompt of the run.
    /// - Returns: The play.
    static func rootPlay(starting name: String, prompt: String) -> ScriptedAgentPlay {
        ScriptedAgentPlay(
            key: rootKey, steps: [startStep(name, prompt: prompt), .finalText(rootText), .finalTextOfLastPrompt])
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

    /// Gives the `.completed` events that the run journal of the transcript
    /// in `directory` recorded for the tool call that started `run`.
    ///
    /// - Parameters:
    ///   - run: The run whose final message the Router recorded.
    ///   - directory: The recording directory of the session of the caller.
    /// - Returns: The events, in file order.
    /// - Throws: The error of `#require` when the run has no context, or the
    ///   error of the read.
    static func posts(of run: AgentRun, in directory: URL?) throws -> [OperationEvent] {
        let token = try #require(run.context?.completionToken)
        return try RecordedTranscript.journaledEvents(in: try #require(directory))
            .filter { $0.kind == .completed && $0.correlationID == token }
    }

    /// Waits for the `runSettled` event of the call that started `run`.
    ///
    /// A root session gives the final message of a run to its model as
    /// mail, after the run ends. The test reads the recording of the root
    /// only after this event.
    ///
    /// - Parameters:
    ///   - run: A run that a root session started.
    ///   - events: The session events of that root session, from before its
    ///     first message.
    /// - Returns: The terminal of the call.
    /// - Throws: The error of `#require` when the run has no context, or when
    ///   the events end before the event.
    static func settlement(of run: AgentRun, in events: AsyncStream<SessionEvent>) async throws -> OperationEvent {
        try await firstSettlement(in: events, token: try #require(run.context?.completionToken))
    }

    /// Waits for the first `runSettled` event of a session, or of the call
    /// `token`. The body of `start agent` adds its run before the run can
    /// settle, thus a test reads the runs of a caller after this event.
    ///
    /// - Parameters:
    ///   - events: The session events, from before the first message.
    ///   - token: The completion token of the call, or `nil` for each call.
    /// - Returns: The terminal of the first run that settled.
    /// - Throws: The error of `#require` when the events end first.
    static func firstSettlement(
        in events: AsyncStream<SessionEvent>, token: String? = nil
    ) async throws -> OperationEvent {
        var terminals = events.compactMap { event -> OperationEvent? in
            if case .runSettled(let terminal) = event, token == nil || terminal.correlationID == token {
                terminal
            } else {
                nil
            }
        }.makeAsyncIterator()
        return try #require(await terminals.next())
    }

    /// `true` when `state` failed with ``AgentRunFailure/modelFailed(_:)``.
    ///
    /// - Parameter state: The state of a run.
    /// - Returns: `true` for that failure.
    private static func isModelFailure(_ state: AgentRunState) -> Bool {
        if case .failed(.modelFailed) = state { return true }
        return false
    }

    /// Reads the report of `run` until it holds the waiting sentence for one
    /// child.
    ///
    /// - Parameter run: A run that waits for one child after its task answer.
    /// - Returns: The report.
    /// - Throws: `CancellationError` when the test is cancelled.
    private static func waitingReport(of run: AgentRun) async throws -> String {
        while !run.report.contains(waitingForOneText) {
            try await Task.sleep(for: pollInterval)
        }
        return run.report
    }

    @Test(
        "a run with two children ends after both final messages were delivered and answered",
        .timeLimit(.minutes(1)))
    func leadJoinsBothResults() async throws {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                Self.parentPlay(
                    Self.leadKey, children: [(Self.reviewer, Self.reviewerKey), (Self.testWriter, Self.testWriterKey)]),
                ScriptedAgentPlay(key: Self.reviewerKey, steps: [.finalText(Self.reviewerText)]),
                ScriptedAgentPlay(key: Self.testWriterKey, steps: [.finalText(Self.testWriterText)])
            ]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let lead = try await runner.start(Self.lead, prompt: Self.leadKey)
        let result = try await lead.result()
        let children = await runner.runs(caller: lead.id)
        let prompts = harness.script.prompts

        #expect(children.map(\.agent.id).sorted() == [Self.reviewer, Self.testWriter])
        #expect(children.allSatisfy { $0.depth == AgentRunner.hostDepth + 1 })
        #expect(children.allSatisfy { child in result.contains(child.report) })
        #expect(children.allSatisfy { child in prompts.count(where: { $0.contains(child.report) }) == 1 })
        #expect(prompts.last.map(result.contains) == true)
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

        #expect(report.hasPrefix("\(lead.subject) is running. \(Self.waitingForOneText)\n"))
        #expect(stateWhileWaiting == .running)
        #expect(child.state == .finished(Self.reviewerText))
        #expect(result.contains(Self.reviewerText))
    }

    @Test("a failing parent cancels its open child first, and the Router records both final messages",
        .timeLimit(.minutes(1)))
    func failingParentCancelsChildThenPosts() async throws {
        let gate = ScriptedGate()
        let failGate = ScriptedGate()
        let leadSteps: [ScriptedAgentStep] = [
            Self.startStep(Self.reviewer, prompt: Self.reviewerKey), .wait(failGate), .fail(ScriptedFailure.broken)
        ]
        let harness = try await AgentsToolHarness.make(
            script: ScriptedAgentScript([
                Self.rootPlay(starting: Self.lead, prompt: Self.leadKey),
                ScriptedAgentPlay(key: Self.leadKey, steps: leadSteps),
                ScriptedAgentPlay(key: Self.reviewerKey, steps: [.wait(gate), .finalText(Self.reviewerText)])
            ]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)
        let rootEvents = await root.streamSessionEvents()

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        await gate.waitForArrival()
        await harness.tool.context.startedRuns.waitForStarts()
        let lead = try await Self.onlyRun(of: harness.runner, caller: root.id)
        let child = try await Self.onlyRun(of: harness.runner, caller: lead.id)
        failGate.open()
        let leadFinal = await lead.finalState()
        let childStateAtParentEnd = child.state
        _ = try await Self.settlement(of: lead, in: rootEvents)
        let leadPosts = try Self.posts(of: lead, in: root.recordingDirectory)
        let childPosts = try Self.posts(of: child, in: lead.recordingDirectory)
        await root.close()

        #expect(Self.isModelFailure(leadFinal))
        #expect(childStateAtParentEnd == .cancelled)
        #expect(childPosts.map(\.detail) == ["\(child.subject) was cancelled."])
        #expect(leadPosts.map(\.detail) == [lead.report])
    }

    @Test("cancel() on a parent with an open child cancels the child and waits for it",
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
        let rootEvents = await root.streamSessionEvents()

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        await gate.waitForArrival()
        await harness.tool.context.startedRuns.waitForStarts()
        let lead = try await Self.onlyRun(of: harness.runner, caller: root.id)
        let child = try await Self.onlyRun(of: harness.runner, caller: lead.id)
        lead.cancel()
        let leadFinal = await lead.finalState()
        let childStateAtParentEnd = child.state
        _ = try await Self.settlement(of: lead, in: rootEvents)
        let leadPosts = try Self.posts(of: lead, in: root.recordingDirectory)
        let childPosts = try Self.posts(of: child, in: lead.recordingDirectory)
        await root.close()

        #expect(leadFinal == .cancelled)
        #expect(childStateAtParentEnd == .cancelled)
        #expect(childPosts.map(\.detail) == ["\(child.subject) was cancelled."])
        #expect(leadPosts.map(\.detail) == ["\(lead.subject) was cancelled."])
    }

    @Test("a root session answers the mail of a finished run with no call of the host",
        .timeLimit(.minutes(1)))
    func rootAnswersMailOfFinishedRun() async throws {
        let harness = try await AgentsToolHarness.make(
            script: ScriptedAgentScript([
                Self.rootPlay(starting: Self.reviewer, prompt: Self.reviewerKey),
                ScriptedAgentPlay(key: Self.reviewerKey, steps: [.finalText(Self.reviewerText)])
            ]))
        defer { try? harness.delete() }
        let root = Self.rootSession(of: harness)
        let rootEvents = await root.streamSessionEvents()
        var mailAnswers = rootEvents.compactMap { event -> SessionAnswer? in
            if case .answered(let answer) = event, answer.messageIds.isEmpty { answer } else { nil }
        }.makeAsyncIterator()

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        let mailAnswer = try #require(await mailAnswers.next())
        let child = try await Self.onlyRun(of: harness.runner, caller: root.id)
        await root.close()

        #expect(child.state == .finished(Self.reviewerText))
        #expect(mailAnswer.reply.contains(child.report))
        #expect(harness.runHarness.script.prompts.last == mailAnswer.reply)
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
        let rootEvents = await root.streamSessionEvents()

        #expect(try await root.respond(to: Self.rootPrompt) == Self.rootText)
        let leadTerminal = try await Self.firstSettlement(in: rootEvents)
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

        #expect(leadTerminal.correlationID == leadToken)
        #expect(rootSpawn == nil)
        #expect(leadSpawn == SessionSidecar.AgentSpawn(parentSessionId: root.id, parentToolCallId: leadToken))
        #expect(childSpawn == SessionSidecar.AgentSpawn(parentSessionId: lead.id, parentToolCallId: childToken))
        #expect(leadPosts.map(\.correlationID) == [leadToken])
    }
}
