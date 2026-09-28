import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsAgents

/// Pins the mount of each call of the `agents` tool (plan.md §9.1, §9.2).
///
/// `start agent` is the one background operation: in a Router session it
/// answers at once with the pending envelope, and the final message of the
/// run comes later as mail. `list agents`, `check agent`, and `cancel agent`
/// are synchronous: they give their real answer in band, with no envelope.
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
    private static func idArguments(_ operation: String, of run: AgentRun) -> String {
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
        let runs = await harness.runner.runs(caller: root.id)
        let run = try #require(runs.first)
        checkArguments.set(Self.idArguments("check agent", of: run))
        cancelArguments.set(Self.idArguments("cancel agent", of: run))
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
}
