import FoundationModels
import FoundationModelsRouter
import Synchronization
import Testing

@testable import FoundationModelsAgents

/// Pins the mount of each call of the `agents` tool (plan.md §9.1, §9.2).
///
/// `start agent` is the one background operation: in a Router session it
/// answers at once with the pending envelope, and the final message of the
/// run comes later as mail. `list agents`, `check agent`, and `cancel agent`
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
    /// envelope has it, pending or settled.
    private static let envelopeMark = #""pending":"#

    /// The mark of a pending envelope.
    private static let pendingMark = #""pending":true"#

    /// The JSON arguments of the scripted `start agent` call.
    private static let startArguments = #"{"op": "start agent", "name": "code-reviewer", "prompt": "\#(childPrompt)"}"#

    /// The JSON arguments of the scripted `list agents` call.
    private static let listArguments = #"{"op": "list agents"}"#

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

    /// A scripted call of the `agents` tool.
    ///
    /// - Parameter argumentsJSON: The JSON arguments of the call.
    /// - Returns: The step.
    private static func toolStep(_ argumentsJSON: String) -> ScriptedAgentStep {
        .toolCall(name: ToolVocabulary.agentsToolName, argumentsJSON: argumentsJSON)
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

    /// With no inline settle grace, no call of the tool waits for a time and
    /// then answers with an envelope: a synchronous op waits for its real
    /// answer, and `start agent` answers with the envelope at once.
    @Test("the tool has no inline settle grace")
    func toolHasNoInlineSettleGrace() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        #expect(harness.tool.inlineSettleGrace == nil)
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
            Self.toolStep(Self.startArguments), .finalText(Self.rootText),
            Self.toolStep(Self.listArguments),
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
        let root = harness.runHarness.profile.standard.makeSession(instructions: Self.rootKey, tools: [harness.tool])
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
        let record = MadeToolRecord()
        let harness = try await AgentsToolHarness.make(script: Self.leadScript(rootSteps: [Self.probeStep]))
        defer { try? harness.delete() }
        let maker = record.wrapping(AgentRun.agentsTool(of: harness.runner))
        let probe = AgentStartProbe { context in
            await harness.runner.start(
                try harness.runHarness.request(
                    NestedRunTests.lead, prompt: Self.leadPrompt, context: context, agentsTool: maker))
        }
        let root = harness.runHarness.profile.standard.makeSession(instructions: Self.rootKey, tools: [probe])

        _ = try await root.respond(to: Self.rootPrompt)
        let started = try #require(probe.started)
        _ = await started.run.finalState()
        await root.close()
        let call = try #require(started.context)
        let context = try #require(record.tools.first).context
        let link = try #require(context.callerLink)

        #expect(record.tools.count == 1)
        #expect(link.sessionID == root.id)
        #expect(link.call.completionToken == call.completionToken)
        #expect(context.grant == .full)
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

    /// The prompt of the lead run. It is also the key of its play.
    private static let leadPrompt = "mount-lead-key: divide the review"

    /// The arguments of the scripted call of the probe tool.
    private static let probeArguments = #"{"text":"start"}"#

    /// The step of the root session that starts the lead run with the probe
    /// tool.
    private static let probeStep =
        ScriptedAgentStep.toolCall(name: AgentStartProbe.toolName, argumentsJSON: probeArguments)

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
