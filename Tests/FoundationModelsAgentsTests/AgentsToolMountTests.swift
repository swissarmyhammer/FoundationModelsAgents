import FoundationModels
import FoundationModelsRouter
import Synchronization
import Testing

@testable import FoundationModelsAgents

/// Pins the mount of each call of the `agents` tool (plan.md §9.1, §9.2).
///
/// `start agent` is the one background operation: in a Router session it
/// waits for the run up to the settle period of the session. A run that
/// continues gives the pending envelope, and the final message of the run
/// comes later as mail. The harness sets the settle period to `0`, thus each
/// call gives the envelope at once. `list agents`, `check agent`, and `cancel agent`
/// are synchronous: they give their real answer in band, with no envelope.
///
/// The suite also pins the caller link of the tool: the tool of a run that a
/// call started knows the session and the call of its caller. The tool of a
/// host session and of a host-started run has no caller link.
@Suite("Agents tool mount")
struct AgentsToolMountTests {
    /// The key of the play of the root session. It is its instructions.
    private static let rootKey = "mount-root-play-key"

    /// The first prompt of the root session.
    private static let rootPrompt = "Give the review to an agent."

    /// The second prompt of the root session.
    private static let nextPrompt = "Tell me about the agents and your run."

    /// The answer of each turn of the root session.
    private static let rootText = "Done."

    /// The prompt of the child run. It is also the key of its play.
    private static let childPrompt = "mount-child-key: review the parser"

    /// The final text of the child run.
    private static let childText = "The parser is correct."

    /// The key of the `pending` field of a `PendingRunEnvelope`. Each
    /// envelope has it.
    private static let envelopeMark = #""pending":"#

    /// The mark of a pending envelope.
    private static let pendingMark = #""pending":true"#

    /// The JSON arguments of the scripted `start agent` call.
    private static let startArguments = #"{"op": "start agent", "name": "code-reviewer", "prompt": "\#(childPrompt)"}"#

    /// A completion token of a `start agent` call.
    private static let completionToken = "01M3N00000000000000000TOKN"

    /// The `next` sentence of the pending envelope of `start agent`, word for
    /// word from plan.md §9.2. The Router delivers the final message only
    /// after the answer of the model ends, thus the sentence tells the model
    /// to end its answer.
    private static let collectSentence = """
        This agent works in the background. Do not wait for it, and never guess its result. \
        End your answer now, or do other work first: its final message comes to you as a new message \
        after your answer ends. To see its state, call {"op": "check agent", "id": "\(completionToken)"}.
        """

    /// Each op with the mode of its mount. A verb alias gives the mode of
    /// the operation that it names.
    private static let modes: [(op: String, mode: ToolMount.Mode)] = [
        ("start agent", .background),
        ("run agent", .background),
        ("list agents", .runToCompletion),
        ("check agent", .runToCompletion),
        ("status agent", .runToCompletion),
        ("cancel agent", .runToCompletion)
    ]

    /// The JSON arguments of a scripted call that names the run `run`.
    ///
    /// - Parameters:
    ///   - operation: The op of the call.
    ///   - run: The run.
    /// - Returns: The JSON text.
    private static func idArguments(for operation: String, of run: AgentRun) -> String {
        #"{"op": "\#(operation)", "id": "\#(run.id)"}"#
    }

    @Test("start agent is background, and list, check, and cancel agent are synchronous", arguments: modes)
    func mountOfEachOperation(_ call: (op: String, mode: ToolMount.Mode)) async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }
        let arguments = try GeneratedContent(json: #"{"op": "\#(call.op)"}"#)

        #expect(harness.tool.mount(for: arguments)?.mode == call.mode)
    }

    /// A mount with no timeout runs its call to the end, however long the
    /// call takes. Thus a synchronous op gives its real answer in band after
    /// any time, and the Router never cuts a `start agent` body.
    @Test("the mount of each op has no timeout", arguments: modes)
    func mountOfEachOperationHasNoTimeout(_ call: (op: String, mode: ToolMount.Mode)) async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }
        let arguments = try GeneratedContent(json: #"{"op": "\#(call.op)"}"#)

        #expect(harness.tool.mount(for: arguments) == ToolMount(mode: call.mode, timeout: nil))
    }

    /// The tool states no settle period of its own. Thus `start agent` uses
    /// the settle period that the session configured: a run that ends in that
    /// time gives its final message in band, and a run that continues gives
    /// the pending envelope. Read outside a mount, the default of the
    /// protocol gives `ToolMount.defaultInlineSettleGrace`.
    @Test("the tool uses the configured settle period, and states none of its own")
    func toolUsesTheConfiguredSettleGrace() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        #expect(harness.tool.inlineSettleGrace == ToolMount.defaultInlineSettleGrace)
    }

    @Test("the pending envelope tells the model to end its answer to get the final message as mail")
    func collectSentenceTellsTheModelToEndItsAnswer() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        #expect(harness.tool.collectInstruction(forCompletionToken: Self.completionToken) == Self.collectSentence)
    }

    @Test(
        "in a Router session, list, check, and cancel agent give their real answer in band, with no envelope",
        .timeLimit(.minutes(1)))
    func listCheckAndCancelAnswerInBand() async throws {
        let gate = ScriptedGate()
        let checkArguments = ScriptedArguments()
        let cancelArguments = ScriptedArguments()
        let rootSteps: [ScriptedAgentStep] = [
            .agentsToolCall(Self.startArguments), .finalText(Self.rootText),
            .listAgents,
            .deferredToolCall(name: ToolVocabulary.agentsToolName, arguments: checkArguments),
            .deferredToolCall(name: ToolVocabulary.agentsToolName, arguments: cancelArguments),
            .finalText(Self.rootText), .finalTextOfLastPrompt
        ]
        let harness = try await AgentsToolHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: Self.rootKey, steps: rootSteps),
                ScriptedAgentPlay(key: Self.childPrompt, steps: [.wait(gate), .finalText(Self.childText)])
            ]))
        defer { try? harness.delete() }
        let root = harness.makeRootSession(instructions: Self.rootKey)
        let events = await root.streamSessionEvents()

        _ = try await root.respond(to: Self.rootPrompt)
        await gate.waitForArrival()
        // The Router answers the start agent call before its body adds the
        // run. Wait until the body of the call added its run.
        await harness.tool.context.startedRuns.waitForStarts()
        let runs = await harness.runner.runs(caller: root.id)
        let run = try #require(runs.first)
        checkArguments.set(Self.idArguments(for: "check agent", of: run))
        cancelArguments.set(Self.idArguments(for: "cancel agent", of: run))
        let listText = try await harness.call("list agents")
        let checkText = run.report
        _ = try await root.respond(to: Self.nextPrompt)
        let outputs = harness.runHarness.script.toolOutputs
        _ = try await NestedRunTests.settlement(of: run, in: events)
        await root.close()

        #expect(runs.count == 1)
        #expect(outputs.first?.contains(Self.pendingMark) == true)
        let inBand = Array(outputs.dropFirst())
        #expect(inBand.dropLast() == [listText, checkText])
        #expect(inBand.last?.hasPrefix("The cancel of \(run.subject) was sent") == true)
        #expect(!inBand.contains { $0.contains(Self.envelopeMark) })
    }

    // MARK: - The caller link

    @Test("the tool of a child run with an Agent grant knows the caller session and the start call",
          .timeLimit(.minutes(1)))
    func childToolKnowsItsCaller() async throws {
        let harness = try await AgentsToolHarness.make(script: Self.leadScript(rootSteps: [Self.probeStep]))
        defer { try? harness.delete() }

        let child = try await Self.calledRun(of: NestedRunTests.lead, in: harness, runner: harness.runner)
        let context = try #require(child.tools.first).context
        let link = try #require(context.callerLink)

        #expect(child.tools.count == 1)
        #expect(link.sessionID == child.rootID)
        #expect(link.call.completionToken == child.call.completionToken)
        #expect(context.grant == .full)
    }

    // MARK: - The mount table of a run with a caller

    @Test("a run with a caller and an Agent entry at maxDepth gets the messaging tool", .timeLimit(.minutes(1)))
    func agentEntryAtMaxDepthGivesTheMessagingTool() async throws {
        let harness = try await AgentsToolHarness.make(script: Self.leadScript(rootSteps: [Self.probeStep]))
        defer { try? harness.delete() }
        let runner = harness.runHarness.makeRunner(maxDepth: AgentRunner.hostDepth)

        let child = try await Self.calledRun(of: NestedRunTests.lead, in: harness, runner: runner)

        #expect(child.tools.map(\.context.grant) == [.messagingOnly])
        #expect(child.tools.first?.context.callerLink?.sessionID == child.rootID)
    }

    @Test("a run with a caller and a tools key with no Agent entry gets the messaging tool",
          .timeLimit(.minutes(1)))
    func toolsKeyWithNoAgentEntryGivesTheMessagingTool() async throws {
        let harness = try await AgentsToolHarness.make(script: Self.leadScript(rootSteps: [Self.probeStep]))
        defer { try? harness.delete() }

        let child = try await Self.calledRun(of: AgentRunTests.reviewer, in: harness, runner: harness.runner)

        #expect(child.tools.map(\.context.grant) == [.messagingOnly])
        #expect(harness.runHarness.script.toolNames(ofPlay: Self.leadPrompt) == [ToolVocabulary.agentsToolName])
    }

    @Test("a run with a caller and no tools key gets the messaging tool", .timeLimit(.minutes(1)))
    func noToolsKeyGivesTheMessagingTool() async throws {
        let harness = try await AgentsToolHarness.make(script: Self.leadScript(rootSteps: [Self.probeStep]))
        defer { try? harness.delete() }

        let child = try await Self.calledRun(of: Self.testWriter, in: harness, runner: harness.runner)

        #expect(child.tools.map(\.context.grant) == [.messagingOnly])
        #expect(harness.runHarness.script.toolNames(ofPlay: Self.leadPrompt) == [ToolVocabulary.agentsToolName])
    }

    @Test("a run with a caller whose disallowedTools denies the agents tool gets no tool",
          .timeLimit(.minutes(1)), arguments: ["Agent", ToolVocabulary.agentsToolName])
    func disallowedAgentsToolGivesNoTool(entry: String) async throws {
        let layer = try TemporaryLayer.make(holding: [
            "agents/\(Self.denier).md": """
                ---
                name: \(Self.denier)
                description: Works alone, with no agents tool.
                disallowedTools: \(entry)
                ---

                You work alone.
                """
        ])
        defer { try? layer.delete() }
        let harness = try await AgentsToolHarness.make(
            script: Self.leadScript(rootSteps: [Self.probeStep]), registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }

        let child = try await Self.calledRun(of: Self.denier, in: harness, runner: harness.runner)

        #expect(child.tools.isEmpty)
        #expect(harness.runHarness.script.toolNames(ofPlay: Self.leadPrompt) == [])
    }

    @Test("a host-started run with no Agent entry gets no tool", .timeLimit(.minutes(1)))
    func hostStartedRunWithNoGrantGetsNoTool() async throws {
        let record = MadeToolRecord()
        let harness = try await AgentsToolHarness.make(script: Self.leadScript(rootSteps: []))
        defer { try? harness.delete() }

        let run = try await harness.runHarness.start(
            Self.testWriter, prompt: Self.leadPrompt,
            agentsTool: record.wrapping(AgentRun.agentsTool(of: harness.runner)))
        _ = await run.finalState()

        #expect(record.tools.isEmpty)
        #expect(harness.runHarness.script.toolNames(ofPlay: Self.leadPrompt) == [])
    }

    @Test("a host-started run with an Agent entry at maxDepth gets no tool", .timeLimit(.minutes(1)))
    func hostStartedRunAtMaxDepthGetsNoTool() async throws {
        let harness = try await AgentsToolHarness.make(script: Self.leadScript(rootSteps: []))
        defer { try? harness.delete() }
        let runner = harness.runHarness.makeRunner(maxDepth: AgentRunner.hostDepth)

        let run = try await runner.start(NestedRunTests.lead, prompt: Self.leadPrompt)

        #expect(try await run.result() == Self.childText)
        #expect(harness.runHarness.script.toolNames(ofPlay: Self.leadPrompt) == [])
    }

    @Test("the tool of a host-started run has no caller link", .timeLimit(.minutes(1)))
    func hostStartedRunToolHasNoCallerLink() async throws {
        let record = MadeToolRecord()
        let harness = try await AgentsToolHarness.make(script: Self.leadScript(rootSteps: []))
        defer { try? harness.delete() }

        let run = try await harness.runHarness.start(
            NestedRunTests.lead, prompt: Self.leadPrompt,
            agentsTool: record.wrapping(AgentRun.agentsTool(of: harness.runner)))
        _ = await run.finalState()
        let context = try #require(record.tools.first).context

        #expect(record.tools.count == 1)
        #expect(context.callerLink == nil)
        #expect(context.grant == .full)
    }

    @Test("the tool of a host session has no caller link")
    func hostSessionToolHasNoCallerLink() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        #expect(harness.tool.context.callerLink == nil)
        #expect(harness.tool.context.grant == .full)
    }

    // MARK: - Support of the caller link

    /// The prompt of the run that the probe starts. It is also the key of its
    /// play.
    private static let leadPrompt = "mount-lead-key: divide the review"

    /// The agent of the fixture library with no `tools` key.
    private static let testWriter = "test-writer"

    /// The agent of the temporary layer whose `disallowedTools` key denies
    /// the `agents` tool.
    private static let denier = "denier"

    /// The arguments of the scripted call of the probe tool.
    private static let probeArguments = #"{"text":"start"}"#

    /// The step of the root session that starts the lead run with the probe
    /// tool.
    private static let probeStep =
        ScriptedAgentStep.toolCall(name: AgentStartProbe.toolName, argumentsJSON: probeArguments)

    /// A run that a call of the probe tool in a root session started.
    private struct CalledRun {
        /// Each `agents` tool that the maker of the run made.
        let tools: [AgentsTool]

        /// The context of the probe call that started the run.
        let call: ToolContext

        /// The id of the root session.
        let rootID: ULID
    }

    /// Starts a run of `agent` from a call of the probe tool in a root
    /// session, and waits until the run ends.
    ///
    /// The root session plays ``rootKey``, and the run plays ``leadPrompt``.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent of the run.
    ///   - harness: The harness of the profile and the registry.
    ///   - runner: The runner that starts the run. Its environment gives the
    ///     depth limit.
    /// - Returns: The tools that the maker of the run made, the probe call,
    ///   and the id of the root session.
    /// - Throws: The error of the root session, or a `#require` failure when
    ///   the probe started no run.
    private static func calledRun(
        of agent: String, in harness: AgentsToolHarness, runner: AgentRunner
    ) async throws -> CalledRun {
        let record = MadeToolRecord()
        let maker = record.wrapping(AgentRun.agentsTool(of: runner))
        let probe = AgentStartProbe { context in
            await runner.start(
                try harness.runHarness.request(agent, prompt: leadPrompt, context: context, agentsTool: maker))
        }
        let root = AgentRunHarness.makeRootSession(
            on: harness.runHarness.profile.standard, instructions: rootKey, tools: [probe])
        _ = try await root.respond(to: rootPrompt)
        let started = try #require(probe.started)
        _ = await started.run.finalState()
        await root.close()
        return CalledRun(tools: record.tools, call: try #require(started.context), rootID: root.id)
    }

    /// Makes the script of a root session and of one lead run.
    ///
    /// - Parameter rootSteps: The tool calls of the root session before its
    ///   answer.
    /// - Returns: The script. The lead run gives its final text at once.
    private static func leadScript(rootSteps: [ScriptedAgentStep]) -> ScriptedAgentScript {
        ScriptedAgentScript([
            ScriptedAgentPlay(key: rootKey, steps: rootSteps + [.finalText(rootText)]),
            ScriptedAgentPlay(key: leadPrompt, steps: [.finalText(childText)])
        ])
    }
}

/// Keeps each `agents` tool that a wrapped maker made, in the order of the
/// calls.
private final class MadeToolRecord: Sendable {
    /// The tools that the maker made.
    private let made = Mutex<[any Tool]>([])

    /// The tools that the maker made, each as an `AgentsTool`. A tool of a
    /// different type is not in the list.
    var tools: [AgentsTool] {
        made.withLock { $0 }.compactMap { $0 as? AgentsTool }
    }

    /// Wraps `maker`: the new maker gives the tool of `maker` and keeps it.
    ///
    /// - Parameter maker: The maker of the `agents` tool of a run.
    /// - Returns: The maker that keeps each tool.
    func wrapping(_ maker: @escaping AgentRunRequest.AgentsToolMaker) -> AgentRunRequest.AgentsToolMaker {
        { parent, callerLink, grant, allowedNames in
            let tool = try await maker(parent, callerLink, grant, allowedNames)
            self.made.withLock { $0.append(tool) }
            return tool
        }
    }
}
