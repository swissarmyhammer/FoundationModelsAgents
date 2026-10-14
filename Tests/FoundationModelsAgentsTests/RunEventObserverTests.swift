import FoundationModels
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Synchronization
import Testing
import ULID

/// The observer of the session events of each run
/// (`AgentEnvironment.runEventObserver`).
///
/// A scripted parent run starts one child run, and the child calls the Read
/// tool. The body of the Read tool holds until the observer gets the open
/// `toolInvocation` record of that tool run. Thus the run finishes only when
/// the observer gets the open record while the body runs, before the body
/// gives its output.
@Suite("The run event observer gets the session events of each run")
struct RunEventObserverTests {
    /// The name of the tool that the child calls. The fixture agent
    /// code-reviewer lists it in its `tools` key.
    private static let readToolName = "Read"

    /// The output of the Read tool.
    private static let readOutput = "read-output-4d2a"

    /// The task text of the parent run. It is the key of its play.
    private static let leadTask = "run-event-observer-lead-key: divide the task"

    /// The task text of the child run. It is the key of its play.
    private static let reviewerTask = "run-event-observer-reviewer-key: review the parser"

    /// The answer of the child run.
    private static let reviewerAnswer = "The parser is correct."

    /// The script: the lead starts code-reviewer, and code-reviewer calls
    /// the Read tool, then answers.
    private static var script: ScriptedAgentScript {
        ScriptedAgentScript([
            NestedRunTests.parentPlay(leadTask, children: [(NestedRunTests.reviewer, reviewerTask)]),
            ScriptedAgentPlay(
                key: reviewerTask,
                steps: [
                    .toolCall(name: readToolName, argumentsJSON: #"{"text": "parser.swift"}"#),
                    .finalText(reviewerAnswer)
                ])
        ])
    }

    @Test(
        "the observer gets the open record of a tool run of a child run while the body of the tool runs")
    func observerGetsOpenRecordBeforeTheToolOutput() async throws {
        let observed = ObservedRunEvents(toolName: Self.readToolName)
        var tools = ToolCatalog()
        tools.register(Self.readToolName) {
            GatedTool(name: Self.readToolName, output: Self.readOutput, observed: observed)
        }
        let harness = try await AgentRunHarness.make(
            script: Self.script, tools: tools, runEventObserver: observed.observer)
        defer { try? harness.delete() }

        let runner = harness.makeRunner()
        let lead = try await runner.start(NestedRunTests.lead, prompt: Self.leadTask)
        _ = try await lead.result()

        let child = try #require(await runner.runs(caller: lead.id).first)
        let records = observed.toolRecords(named: Self.readToolName)
        let open = try #require(records.first)
        #expect(open.runID == child.id)
        #expect(open.record.closedAt == nil)
        #expect(open.record.sessionID == child.id)
        #expect(records.count == 2)
        #expect(records.last?.record.closedAt != nil)
        #expect(records.last?.record.correlationID == open.record.correlationID)
        #expect(observed.bodyTokens == [open.record.correlationID])
        #expect(observed.runIDs.isSuperset(of: [lead.id, child.id]))
    }
}

/// The events that the observer got, and the gate that the observer opens
/// when it gets the open record of the watched tool.
///
/// A class, because the observer and the test share it. A `Mutex` guards
/// the state, thus the `Sendable` conformance is compiler-checked.
private final class ObservedRunEvents: Sendable {
    /// One `toolInvocation` record, with the id of its run.
    struct ToolRecord: Sendable {
        /// The id of the run that gave the event.
        let runID: ULID

        /// The record.
        let record: ToolInvocationRecord
    }

    /// The state that the lock guards.
    private struct State {
        /// The id of each run that gave an event.
        var runIDs: Set<ULID> = []

        /// Each `toolInvocation` record, in the order of the calls.
        var toolRecords: [ToolRecord] = []

        /// The completion token of each body of the watched tool, in the
        /// order of the calls.
        var bodyTokens: [String] = []
    }

    /// The name of the watched tool.
    let toolName: String

    /// The gate that the observer opens when it gets the open record of the
    /// watched tool. The body of that tool waits on it.
    let openRecordGate = ScriptedGate()

    /// The state.
    private let state = Mutex(State())

    /// Makes an empty record of events.
    ///
    /// - Parameter toolName: The name of the watched tool.
    init(toolName: String) {
        self.toolName = toolName
    }

    /// The observer to give to the environment.
    var observer: AgentEnvironment.RunEventObserver {
        { [self] run, output in
            observe(output.event, of: run.id)
        }
    }

    /// The id of each run that gave an event.
    var runIDs: Set<ULID> {
        state.withLock { $0.runIDs }
    }

    /// The completion token of each body of the watched tool.
    var bodyTokens: [String] {
        state.withLock { $0.bodyTokens }
    }

    /// Gives the `toolInvocation` records of one tool, in the order of the
    /// calls.
    ///
    /// - Parameter name: The name of the tool.
    /// - Returns: The records.
    func toolRecords(named name: String) -> [ToolRecord] {
        state.withLock { $0.toolRecords.filter { $0.record.tool == name } }
    }

    /// Records the completion token of one body of the watched tool.
    ///
    /// - Parameter token: The completion token.
    func recordBody(token: String) {
        state.withLock { $0.bodyTokens.append(token) }
    }

    /// Records one event, and opens the gate at the open record of the
    /// watched tool.
    ///
    /// - Parameters:
    ///   - event: The event.
    ///   - runID: The id of the run that gave the event.
    private func observe(_ event: SessionEvent, of runID: ULID) {
        state.withLock { state in
            state.runIDs.insert(runID)
            if case .toolInvocation(let record, _) = event {
                state.toolRecords.append(ToolRecord(runID: runID, record: record))
            }
        }
        if case .toolInvocation(let record, _) = event, record.tool == toolName, record.closedAt == nil {
            openRecordGate.open()
        }
    }
}

/// A tool whose body holds until a gate opens, then gives a fixed output.
///
/// The body records its completion token first, thus the test can match the
/// body with the open record that the observer got.
private struct GatedTool: Tool {
    /// The arguments of the tool: one text.
    @Generable
    struct Arguments {
        /// A text that the tool ignores.
        let text: String
    }

    /// The name of the tool.
    let name: String

    /// The description of the tool.
    let description = "A tool that holds until the observer gets its open record."

    /// The output of the tool.
    let output: String

    /// The record of the observer. Its gate holds the body.
    let observed: ObservedRunEvents

    /// Records the completion token of the tool run, waits on the gate, and
    /// gives the output.
    ///
    /// - Parameter arguments: The arguments, which the tool ignores.
    /// - Returns: ``output``.
    /// - Throws: `CancellationError` when the task is cancelled.
    func call(arguments: Arguments) async throws -> String {
        observed.recordBody(token: ToolContext.current?.completionToken ?? "")
        try await observed.openRecordGate.wait()
        return output
    }
}
