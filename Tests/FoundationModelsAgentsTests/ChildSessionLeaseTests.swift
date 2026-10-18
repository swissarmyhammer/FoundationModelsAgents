import FoundationModels
@testable import FoundationModelsAgents
import FoundationModelsExtras
@testable import FoundationModelsRouter
import Testing
import ULID

/// Pins the work of a child in the registry of its parent: the `start agent`
/// call of the child holds one `childSession` lease in the registry of the
/// parent session while the child works, and the work of the child stays in
/// the registry of the child.
///
/// The root session of the host has the `agents` tool. Its `start agent`
/// call starts one run of ``worker``. The tests read the registry of the
/// root and of the run at fixed points: a gate in the model of the run, a
/// gate in the tool of the run, or a question of the run. They use no clock.
@Suite("Child session leases")
struct ChildSessionLeaseTests {
    /// The agent that the root starts.
    private static let worker = "lease-worker"

    /// The agent that starts ``worker``: the middle level of the grandchild
    /// test.
    private static let lead = "lease-lead"

    /// The key of the play of the lead.
    private static let leadKey = "lease-lead-key: give the work to the worker"

    /// The name of the tool that asks the user.
    private static let askToolName = "ask"

    /// The name of the tool that reads the session tree.
    private static let probeToolName = "probe"

    /// The instructions of the root session. It is also the key of its play.
    private static let rootKey = "lease-root-key"

    /// The first prompt of the root session.
    private static let rootPrompt = "Give the work to an agent."

    /// The key of the play of the worker.
    private static let workerKey = "lease-worker-key: do the work"

    /// The final text of the worker.
    private static let workerText = "The worker is done."

    /// The agent files of the temporary layer, by path.
    private static let agentFiles = [
        AgentDocumentPath.of(worker): """
            ---
            name: \(worker)
            description: Does one piece of work.
            tools: \(askToolName), \(probeToolName)
            ---

            You do the work.
            """,
        AgentDocumentPath.of(lead): """
            ---
            name: \(lead)
            description: Gives the work to the worker.
            tools: Agent(\(worker))
            ---

            You are a lead.
            """,
    ]

    /// The play of a root that starts `name` with `prompt`, answers, then
    /// answers each mail with the text of its last prompt.
    ///
    /// - Parameters:
    ///   - name: The agent that the root starts.
    ///   - prompt: The prompt of that run.
    /// - Returns: The play.
    private static func rootPlay(starting name: String, prompt: String) -> ScriptedAgentPlay {
        ScriptedAgentPlay(
            key: rootKey,
            steps: [NestedRunTests.startStep(name, prompt: prompt), .finalText("I started an agent.")]
                + [ScriptedAgentStep](repeating: .finalTextOfLastPrompt, count: 3))
    }

    /// The play of a worker that waits at `gate` in its model call.
    ///
    /// - Parameter gate: The gate.
    /// - Returns: The play.
    private static func waitingPlay(_ gate: ScriptedGate) -> ScriptedAgentPlay {
        ScriptedAgentPlay(key: workerKey, steps: [.wait(gate), .finalText(workerText)])
    }

    /// The play of a worker that calls `tool` one time.
    ///
    /// - Parameter tool: The name of the tool.
    /// - Returns: The play.
    private static func callingPlay(_ tool: String) -> ScriptedAgentPlay {
        ScriptedAgentPlay(
            key: workerKey,
            steps: [.toolCall(name: tool, argumentsJSON: #"{"text": "parser.swift"}"#), .finalText(workerText)]
                + [ScriptedAgentStep](repeating: .finalTextOfLastPrompt, count: 2))
    }

    /// The parts of one test.
    private struct Parts {
        /// The root session with the `agents` tool.
        let root: any RoutedSession

        /// The runner of the runs of the root.
        let runner: AgentRunner

        /// The calls of the probe tool.
        let probes: TreeProbeRecord

        /// The registry of the root session.
        var rootRegistry: WorkRegistry {
            ChildSessionLeaseTests.registry(of: root)
        }

        /// The one run of the root.
        ///
        /// - Returns: The run.
        /// - Throws: The error of `#require` when the root started no run.
        func run() async throws -> AgentRun {
            try await NestedRunTests.onlyRun(of: runner, caller: root.id)
        }

        /// The `childSession` leases of the root.
        var childLeases: [WorkItem] {
            rootRegistry.openWork.filter { $0.kind == .childSession }
        }
    }

    /// The registry of `session`.
    ///
    /// - Parameter session: A session of the router.
    /// - Returns: The registry of the session.
    static func registry(of session: any RoutedSession) -> WorkRegistry {
        guard let actor = session as? RoutedSessionActor else {
            Issue.record("The session is not a Router session.")
            return WorkRegistry(sessionID: session.id)
        }
        return actor.workRegistry
    }

    /// Makes a temporary layer with ``agentFiles``, a harness with the asking
    /// tool and the probe tool, and a root session with the `agents` tool.
    /// Then it sends the first prompt, runs `body`, closes the root, and
    /// deletes the folders. It closes the root also when `body` throws: the
    /// close cancels each run of the root.
    ///
    /// - Parameters:
    ///   - plays: The plays of the script, after the play of the root.
    ///   - rootPlay: The play of the root. The default starts ``worker``.
    ///   - userPresence: The user presence of the root. The default is
    ///     `.headless`.
    ///   - probeGate: The gate of the probe tool, or `nil`.
    ///   - body: The test. It gets the parts and the iterator of the session
    ///     events of the root, made before the first prompt.
    /// - Throws: The error of the setup, or of `body`.
    private static func withParts(
        plays: [ScriptedAgentPlay],
        rootPlay: ScriptedAgentPlay = rootPlay(starting: worker, prompt: workerKey),
        userPresence: UserPresence = .headless, probeGate: ScriptedGate? = nil,
        _ body: (Parts, inout AsyncStream<SessionOutput>.Iterator) async throws -> Void
    ) async throws {
        let probes = TreeProbeRecord()
        var tools = ToolCatalog()
        tools.register(askToolName) {
            BackgroundAskingTool(asking: AskingTool(name: askToolName, answers: AskedAnswers()))
        }
        tools.register(probeToolName) { TreeProbeTool(name: probeToolName, record: probes, gate: probeGate) }
        try await AgentRunHarness.withLayer(holding: agentFiles, plays: [rootPlay] + plays, tools: tools) { harness in
            let runner = harness.makeRunner()
            let agentsTool = try await AgentsTool.make(context: AgentsToolContext(runner: runner))
            let root = AgentRunHarness.makeRootSession(
                on: harness.profile.standard, instructions: rootKey, tools: [agentsTool], userPresence: userPresence)
            do {
                var events = await root.streamSessionEvents().makeAsyncIterator()
                try root.send(rootPrompt)
                try await body(Parts(root: root, runner: runner, probes: probes), &events)
            } catch {
                await root.close()
                throw error
            }
            await root.close()
        }
    }

    /// Waits until a step of the root arrives at `gate`. The wait also ends
    /// when the root is idle first: then no step can arrive.
    ///
    /// - Parameters:
    ///   - gate: The gate.
    ///   - root: The root session.
    /// - Throws: The error of `#require` when the root was idle first.
    private static func arrival(at gate: ScriptedGate, of root: any RoutedSession) async throws {
        let idle = Task { await root.awaitIdle() }
        defer { idle.cancel() }
        try #require(await gate.waitForArrival(orEndOf: idle))
    }

    /// Reads `events` through the next `workEnded`. It stops with `false` at
    /// the end of the stream: the root closed.
    ///
    /// - Parameter events: The iterator of the session events of the root.
    /// - Returns: `true` when a `workEnded` came.
    private static func nextWorkEnd(in events: inout AsyncStream<SessionOutput>.Iterator) async -> Bool {
        while let output = await events.next() {
            if output.event == .workEnded {
                return true
            }
        }
        return false
    }

    /// Reads `events` up to the first question, and gives it. It stops with
    /// `nil` at the first event that ends the work of the root before a
    /// question came, and at the end of the stream.
    ///
    /// - Parameter events: The iterator of the session events of the root.
    /// - Returns: The question, or `nil`.
    private static func firstQuestion(
        in events: inout AsyncStream<SessionOutput>.Iterator
    ) async -> ElicitationRequest? {
        while let output = await events.next() {
            switch output.event {
            case .elicitationRequested(let operation):
                return operation.elicitation
            case .runSettled, .lost, .cancelled, .answerFailed:
                return nil
            default:
                continue
            }
        }
        return nil
    }

    // MARK: - The lease of the call

    @Test("while the child works, the parent holds one childSession lease of the child, and it ends with the child")
    func theParentIsBusyWhileTheChildWorks() async throws {
        let gate = ScriptedGate()
        try await Self.withParts(plays: [Self.waitingPlay(gate)]) { parts, _ in
            try await Self.arrival(at: gate, of: parts.root)
            let run = try await parts.run()
            let whileWorking = parts.childLeases
            gate.open()
            let final = await run.finalState()

            #expect(whileWorking == [WorkItem(kind: .childSession, id: run.id.description, sessionID: parts.root.id)])
            #expect(final == .finished(Self.workerText))
            #expect(run.childSessionWork.lease == nil)
            #expect(parts.childLeases.isEmpty)
        }
    }

    @Test("the parent has work while the child has work, and reaches no work when the child reaches no work")
    func theParentHasNoWorkWhenTheChildHasNone() async throws {
        let gate = ScriptedGate()
        try await Self.withParts(plays: [Self.callingPlay(Self.probeToolName)], probeGate: gate) { parts, _ in
            try await Self.arrival(at: gate, of: parts.root)
            let run = try await parts.run()
            let child = try #require(run.heldSession)
            let childHadWork = Self.registry(of: child).hasWork
            let rootHadWork = parts.rootRegistry.hasWork
            gate.open()
            let final = await run.finalState()
            let isIdle = await parts.root.awaitIdle()

            #expect(childHadWork)
            #expect(rootHadWork)
            #expect(final == .finished(Self.workerText))
            #expect(run.childSessionWork.lease == nil)
            #expect(isIdle)
            #expect(parts.rootRegistry.hasWork == false)
        }
    }

    @Test("a lease of a tool of the child goes into the registry of the child, never into the registry of the parent")
    func childLeasesStayInTheChild() async throws {
        let gate = ScriptedGate()
        try await Self.withParts(plays: [Self.callingPlay(Self.probeToolName)], probeGate: gate) { parts, _ in
            try await Self.arrival(at: gate, of: parts.root)
            let run = try await parts.run()
            let child = try #require(run.heldSession)
            let probe = try #require(parts.probes.all.first)
            let inChild = Self.registry(of: child).openWork
            let inRoot = parts.rootRegistry.openWork
            gate.open()
            _ = await run.finalState()

            #expect(probe.lease.sessionID == run.id)
            #expect(inChild.contains(probe.lease))
            #expect(inRoot.contains(probe.lease) == false)
            #expect(inRoot.allSatisfy { $0.sessionID == parts.root.id })
        }
    }

    // MARK: - A child that waits only for the user

    @Test("a child that waits only for the user leaves the parent with no work, and the answer gives it work again")
    func aChildThatWaitsForTheUserLeavesTheParentIdle() async throws {
        try await Self.withParts(plays: [Self.callingPlay(Self.askToolName)], userPresence: .interactive) {
            parts, events in
            let question = try #require(await Self.firstQuestion(in: &events))
            let run = try await parts.run()
            try #require(await Self.nextWorkEnd(in: &events))
            let lease = try #require(run.childSessionWork.lease)
            let rootHadWork = parts.rootRegistry.hasWork
            let wasSuspended = lease.isSuspended
            let delivery = await parts.root.respond(
                elicitationId: question.elicitationId.ulidString, response: .accept(content: [:]))
            try #require(delivery == .delivered)
            let final = await run.finalState()

            #expect(rootHadWork == false)
            #expect(wasSuspended)
            if case .finished = final {
            } else {
                Issue.record("The worker did not finish: \(final)")
            }
            #expect(lease.isEnded)
        }
    }

    // MARK: - The cancel and the close of the parent

    @Test("cancelAll of the parent cancels the child and ends its lease in the parent")
    func aCancelOfTheParentEndsTheChildAndItsLease() async throws {
        let gate = ScriptedGate()
        try await Self.withParts(plays: [Self.waitingPlay(gate)]) { parts, _ in
            try await Self.arrival(at: gate, of: parts.root)
            let run = try await parts.run()
            let lease = try #require(run.childSessionWork.lease)
            parts.root.cancelAll()
            let final = await run.finalState()

            #expect(final == .cancelled)
            #expect(lease.isEnded)
            #expect(parts.childLeases.isEmpty)
        }
    }

    @Test("a close of the parent cancels the child and ends its lease in the parent")
    func aCloseOfTheParentEndsTheChildAndItsLease() async throws {
        let gate = ScriptedGate()
        try await Self.withParts(plays: [Self.waitingPlay(gate)]) { parts, _ in
            try await Self.arrival(at: gate, of: parts.root)
            let run = try await parts.run()
            let lease = try #require(run.childSessionWork.lease)
            await parts.root.close()
            let final = await run.finalState()

            #expect(final == .cancelled)
            #expect(lease.isEnded)
        }
    }

    // MARK: - The session tree of the tools of a child

    @Test("a tool of a child sees the parent session and the root session of its tree")
    func aChildToolSeesItsTree() async throws {
        try await Self.withParts(plays: [Self.callingPlay(Self.probeToolName)]) { parts, _ in
            try #require(await parts.root.awaitIdle())
            let run = try await parts.run()
            let probe = try #require(parts.probes.all.first)

            #expect(probe.sessionID == run.id)
            #expect(probe.parentSessionID == parts.root.id)
            #expect(probe.rootSessionID == parts.root.id)
        }
    }

    @Test("a tool of a grandchild sees the child as its parent and the root of the tree as its root")
    func aGrandchildToolSeesItsTree() async throws {
        let plays = [
            NestedRunTests.parentPlay(Self.leadKey, children: [(Self.worker, Self.workerKey)]),
            Self.callingPlay(Self.probeToolName),
        ]
        try await Self.withParts(plays: plays, rootPlay: Self.rootPlay(starting: Self.lead, prompt: Self.leadKey)) {
            parts, _ in
            try #require(await parts.root.awaitIdle())
            let lead = try await parts.run()
            let worker = try await NestedRunTests.onlyRun(of: parts.runner, caller: lead.id)
            let probe = try #require(parts.probes.all.first)

            #expect(probe.sessionID == worker.id)
            #expect(probe.parentSessionID == lead.id)
            #expect(probe.rootSessionID == parts.root.id)
            #expect(probe.lease.sessionID == worker.id)
        }
    }
}
