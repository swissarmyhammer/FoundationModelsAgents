import FoundationModels
import FoundationModelsRouter

/// A session backend that runs a real `LanguageModelSession` over a
/// ``ScriptedAgentModel``.
///
/// Router keeps its own live backend internal, thus the test support has
/// this backend. The real session runs the tool loop: it calls the mounted
/// tools and writes the tool outputs into its transcript. The scripted model
/// only gives the tool calls and the text.
final class ScriptedSessionBackend: LanguageModelSessionBackend {
    /// The model that a fork runs its session over.
    private let model: ScriptedAgentModel

    /// The tools that ``session`` has, and that a fork gets.
    private let tools: [any Tool]

    /// The live session that each call runs through.
    private let session: LanguageModelSession

    /// Makes a backend over a fresh session.
    ///
    /// - Parameters:
    ///   - model: The scripted model.
    ///   - instructions: The session instructions, or `nil`.
    ///   - tools: The tools that the model can call.
    init(model: ScriptedAgentModel, instructions: String?, tools: [any Tool]) {
        self.model = model
        self.tools = tools
        session = LanguageModelSession(model: model, tools: tools, instructions: instructions)
    }

    /// Makes a backend over a session that starts from `transcript`.
    ///
    /// - Parameters:
    ///   - model: The scripted model.
    ///   - transcript: The transcript that the session starts from.
    ///   - tools: The tools that the model can call.
    init(model: ScriptedAgentModel, transcript: Transcript, tools: [any Tool]) {
        self.model = model
        self.tools = tools
        session = LanguageModelSession(model: model, tools: tools, transcript: transcript)
    }

    func respond(to prompt: String, maxTokens: Int?) async throws -> String {
        try await session.respond(to: prompt, options: GenerationOptions(maximumResponseTokens: maxTokens)).content
    }

    /// Answers `prompt` with the scripted text.
    ///
    /// The script sets the text, thus `grammar` does not change it. A test
    /// that needs guided output scripts text that obeys the grammar.
    func respond(to prompt: String, following grammar: Grammar, maxTokens: Int?) async throws -> String {
        try await respond(to: prompt, maxTokens: maxTokens)
    }

    /// Streams the response as the text that each snapshot adds.
    ///
    /// A snapshot that does not extend the text so far gives its full text.
    func streamResponse(to prompt: String, maxTokens: Int?) -> AsyncThrowingStream<String, Error> {
        let session = session
        return AsyncThrowingStream { continuation in
            let relay = Task {
                do {
                    var previous = ""
                    let options = GenerationOptions(maximumResponseTokens: maxTokens)
                    for try await snapshot in session.streamResponse(to: prompt, options: options) {
                        let current = snapshot.content
                        if current != previous {
                            let extends = current.hasPrefix(previous)
                            continuation.yield(extends ? String(current.dropFirst(previous.count)) : current)
                        }
                        previous = current
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in relay.cancel() }
        }
    }

    func makeFork() -> any LanguageModelSessionBackend {
        makeFork(tools: tools)
    }

    func makeFork(tools: [any Tool]) -> any LanguageModelSessionBackend {
        ScriptedSessionBackend(model: model, transcript: session.transcript, tools: tools)
    }

    func replacingTranscript(_ transcript: Transcript) -> any LanguageModelSessionBackend {
        ScriptedSessionBackend(model: model, transcript: transcript, tools: tools)
    }

    func transcriptEntries() -> [Transcript.Entry] {
        Array(session.transcript)
    }

    func usageTokenCounts() -> (input: Int, output: Int)? {
        let usage = session.usage
        return (usage.input.totalTokenCount, usage.output.totalTokenCount)
    }
}

/// A resident model whose sessions run over one ``ScriptedAgentModel``.
///
/// All four factories are written out. The protocol default of the two
/// `tools:` factories DROPS the tools, and a scripted tool call needs them.
struct ScriptedAgentContainer: LoadedLLMContainer {
    /// The model that each session runs over.
    let model: ScriptedAgentModel

    /// The raw model, for `RoutedModel.makeLanguageModel()`.
    var languageModel: any FoundationModels.LanguageModel {
        model
    }

    func makeSession(instructions: String?) -> any LanguageModelSessionBackend {
        makeSession(instructions: instructions, tools: [])
    }

    func makeSession(instructions: String?, tools: [any Tool]) -> any LanguageModelSessionBackend {
        ScriptedSessionBackend(model: model, instructions: instructions, tools: tools)
    }

    func makeSession(transcript: Transcript) -> any LanguageModelSessionBackend {
        makeSession(transcript: transcript, tools: [])
    }

    func makeSession(transcript: Transcript, tools: [any Tool]) -> any LanguageModelSessionBackend {
        ScriptedSessionBackend(model: model, transcript: transcript, tools: tools)
    }
}
