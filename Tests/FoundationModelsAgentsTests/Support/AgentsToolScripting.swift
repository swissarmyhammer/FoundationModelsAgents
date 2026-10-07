import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsAgents

/// Shared helpers for the suites that script calls of the `agents` tool and
/// root sessions that hold the tool.
///
/// Each suite uses these helpers. A suite does not keep a private copy.
extension ScriptedAgentStep {
    /// A scripted call of the `agents` tool.
    ///
    /// - Parameter argumentsJSON: The JSON arguments of the call.
    /// - Returns: The step.
    static func agentsToolCall(_ argumentsJSON: String) -> ScriptedAgentStep {
        .toolCall(name: ToolVocabulary.agentsToolName, argumentsJSON: argumentsJSON)
    }

    /// A pass that calls `list agents` one time.
    static let listAgents = agentsToolCall(AgentsToolArguments.listAgents)
}

/// The JSON arguments of calls of the `agents` tool that more than one suite
/// scripts.
enum AgentsToolArguments {
    /// The JSON arguments of a `list agents` call with no filter.
    static let listAgents = #"{"op": "list agents"}"#

    /// The JSON arguments of a `send agent` call.
    ///
    /// - Parameters:
    ///   - id: The id that the call names.
    ///   - message: The message of the call.
    /// - Returns: The JSON text.
    static func sendAgent(id: String, message: String) -> String {
        #"{"op": "send agent", "id": "\#(id)", "message": "\#(message)"}"#
    }

    /// The JSON arguments of a `send caller` call.
    ///
    /// - Parameter message: The message of the call.
    /// - Returns: The JSON text.
    static func sendCaller(message: String) -> String {
        #"{"op": "send caller", "message": "\#(message)"}"#
    }
}

/// One event of a root session that the message suites read.
enum RootSessionEvent {
    /// A `runMessage` event, with the detail of the event.
    case runMessage(String)

    /// An answer that mail started, with its reply.
    case mailAnswer(String)

    /// The iterator over the events of a root session.
    typealias Iterator = AsyncCompactMapSequence<AsyncStream<SessionEvent>, RootSessionEvent>.AsyncIterator

    /// Gives an iterator over the `runMessage` events and the mail answers
    /// of `root`.
    ///
    /// - Parameter root: The root session. Call this before its first
    ///   message.
    /// - Returns: The iterator.
    static func iterator(of root: any RoutedSession) async -> Iterator {
        await root.streamSessionEvents().compactMap { event -> RootSessionEvent? in
            if case .runMessage(let message) = event {
                return .runMessage(message.detail)
            }
            if case .answered(let answer) = event, answer.messageIds.isEmpty {
                return .mailAnswer(answer.reply)
            }
            return nil
        }.makeAsyncIterator()
    }
}

extension AgentsToolHarness {
    /// Makes a root session of a host that holds the tool of the harness.
    ///
    /// - Parameters:
    ///   - key: The instructions of the session. It is also the key of the
    ///     play of the session in the script.
    ///   - slot: The slot of the profile that the session uses. The default
    ///     is the `standard` slot.
    ///   - extraTools: The tools that the session holds after the tool of the
    ///     harness. The default is no tool.
    /// - Returns: The root session.
    func makeRootSession(
        instructions key: String,
        slot: KeyPath<LanguageModelProfile, RoutedLLM> = \.standard,
        adding extraTools: [any Tool] = []
    ) -> any RoutedSession {
        runHarness.profile[keyPath: slot].makeSession(instructions: key, tools: [tool] + extraTools)
    }

    /// Makes a harness and a root session on the `flash` slot, sends the
    /// first prompt, finds the one run that the root session started, and
    /// gives them to `body`. Then it closes the root session and deletes the
    /// harness.
    ///
    /// The run of the root session is on the `standard` slot. Thus the root
    /// session can answer while its run waits on a gate.
    ///
    /// - Parameters:
    ///   - script: The script of the root session and of its run.
    ///   - telemetry: The telemetry of the router and of each run. The
    ///     default has none of them.
    ///   - rootKey: The instructions of the root session. It is also the key
    ///     of its play.
    ///   - rootPrompt: The first prompt of the root session. Its answer
    ///     starts the run.
    ///   - setUp: Receives the root session before its first message. The
    ///     default does nothing.
    ///   - body: Reads the events of the root session and the run.
    /// - Returns: The value of `body`.
    /// - Throws: The error of the harness, of the root session, of
    ///   `#require` when the root session started no run, or of `body`.
    static func withStartedRun<Value>(
        script: ScriptedAgentScript,
        telemetry: HarnessTelemetry = HarnessTelemetry(),
        rootKey: String,
        rootPrompt: String,
        setUp: (any RoutedSession) -> Void = { _ in },
        body: (inout StartedRootRun) async throws -> Value
    ) async throws -> Value {
        let harness = try await make(script: script, telemetry: telemetry)
        defer { try? harness.delete() }
        let root = harness.makeRootSession(instructions: rootKey, slot: \.flash)
        setUp(root)
        let events = await RootSessionEvent.iterator(of: root)
        _ = try await root.respond(to: rootPrompt)
        await harness.tool.context.startedRuns.waitForStarts()
        let run = try await NestedRunTests.onlyRun(of: harness.runner, caller: root.id)
        var started = StartedRootRun(harness: harness, root: root, run: run, events: events)
        do {
            let value = try await body(&started)
            await root.close()
            return value
        } catch {
            await root.close()
            throw error
        }
    }
}

/// A root session that started one run, which
/// ``AgentsToolHarness/withStartedRun(script:telemetry:rootKey:rootPrompt:setUp:body:)``
/// gives to its body.
struct StartedRootRun {
    /// The harness that holds the tool of the root session.
    let harness: AgentsToolHarness

    /// The root session.
    let root: any RoutedSession

    /// The one run that the root session started.
    let run: AgentRun

    /// The events of the root session that the body did not read yet.
    var events: RootSessionEvent.Iterator

    /// Gives the next event of the root session.
    ///
    /// - Returns: The event.
    /// - Throws: The error of `#require` when the events end.
    mutating func nextEvent() async throws -> RootSessionEvent {
        try #require(await events.next())
    }
}
