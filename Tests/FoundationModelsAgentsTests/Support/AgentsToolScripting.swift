import FoundationModels
import FoundationModelsRouter

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

    /// Gives an iterator over the `runMessage` events and the mail answers
    /// of `root`.
    ///
    /// - Parameter root: The root session. Call this before its first
    ///   message.
    /// - Returns: The iterator.
    static func iterator(
        of root: any RoutedSession
    ) async -> AsyncCompactMapSequence<AsyncStream<SessionEvent>, RootSessionEvent>.AsyncIterator {
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
}
