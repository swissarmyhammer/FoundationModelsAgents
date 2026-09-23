import FoundationModels
import Synchronization

/// One step of a scripted play.
enum ScriptedAgentStep: Sendable {
    /// Calls the mounted tool `name` with the arguments `argumentsJSON`.
    ///
    /// The real `LanguageModelSession` runs the tool and writes its output
    /// into the transcript. The next step then runs.
    case toolCall(name: String, argumentsJSON: String)

    /// Answers with `text`. The turn ends here.
    case finalText(String)

    /// Holds the turn until the test opens the gate. The step gives no
    /// output, thus the next output step runs in the same generation call.
    case wait(ScriptedGate)

    /// Throws `error` from the generation call that reaches the step. The
    /// step gives no output, thus a later call at the same position throws
    /// again.
    case fail(any Error & Sendable)
}

/// The steps that a session plays when its key matches.
struct ScriptedAgentPlay: Sendable {
    /// The text that selects the play.
    ///
    /// The play matches a session when the session instructions or the first
    /// prompt of the session contain this text.
    let key: String

    /// The steps of the play, in order. They continue across the turns of
    /// one session.
    let steps: [ScriptedAgentStep]
}

/// A failure of a scripted generation call.
enum ScriptedAgentModelError: Error, Equatable {
    /// No play key is in the session instructions or in the first prompt.
    case noMatchingPlay(instructions: String, firstPrompt: String)

    /// The session asked for one more output after the last step of the play.
    case playExhausted(key: String)
}

/// The script that each ``ScriptedAgentModel`` of one profile plays.
///
/// The script also records each prompt that the model gets, thus a test
/// reads the prompts back from the script it made.
///
/// A class, because each slot model and the test share one script. The
/// identity of the script is the cache key of the executor. A `Mutex`
/// guards the prompt log, thus the `Sendable` conformance is compiler-checked.
final class ScriptedAgentScript: Sendable {
    /// The plays, in match order. The first play that matches wins.
    let plays: [ScriptedAgentPlay]

    /// The prompts that the model got, in arrival order.
    private let promptLog = Mutex<[String]>([])

    /// Makes a script of `plays`.
    ///
    /// - Parameter plays: The plays, in match order.
    init(_ plays: [ScriptedAgentPlay]) {
        self.plays = plays
    }

    /// The prompts that the model got, in arrival order. A tool round of a
    /// turn gives no new prompt, thus each turn records its prompt one time.
    var prompts: [String] {
        promptLog.withLock { $0 }
    }

    /// Records `prompt`.
    ///
    /// - Parameter prompt: The prompt that the model got.
    func record(prompt: String) {
        promptLog.withLock { $0.append(prompt) }
    }

    /// The play whose key is in `instructions` or in `firstPrompt`.
    ///
    /// - Parameters:
    ///   - instructions: The text of the session instructions.
    ///   - firstPrompt: The text of the first prompt of the session.
    /// - Returns: The first play that matches.
    /// - Throws: ``ScriptedAgentModelError/noMatchingPlay(instructions:firstPrompt:)``
    ///   when no play matches.
    func play(instructions: String, firstPrompt: String) throws -> ScriptedAgentPlay {
        let match = plays.first { play in
            instructions.contains(play.key) || firstPrompt.contains(play.key)
        }
        if let match {
            return match
        }
        throw ScriptedAgentModelError.noMatchingPlay(instructions: instructions, firstPrompt: firstPrompt)
    }
}

/// A tool-calling `LanguageModel` that plays a ``ScriptedAgentScript``.
///
/// The model keeps no generation state. Each generation call reads the full
/// transcript that the session gives it, and counts the tool calls and the
/// responses in it. That count is the position in the play. Thus the play
/// continues across tool rounds and across turns of one session.
struct ScriptedAgentModel: LanguageModel {
    /// The executor that plays the script.
    typealias Executor = ScriptedAgentExecutor

    /// The script that the model plays.
    let script: ScriptedAgentScript

    /// Tool calling only. Without it, the SDK refuses a session with tools.
    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.toolCalling])
    }

    /// The cache key of the executor: the identity of the script.
    var executorConfiguration: ScriptedAgentExecutor.Configuration {
        ScriptedAgentExecutor.Configuration(script: ObjectIdentifier(script))
    }
}

/// The executor of ``ScriptedAgentModel``: it emits the next output step of
/// the play.
struct ScriptedAgentExecutor: LanguageModelExecutor {
    /// The cache key that the SDK makes and reuses the executor by.
    struct Configuration: Sendable, Hashable {
        /// The identity of the script that the model plays.
        let script: ObjectIdentifier
    }

    /// The model that this executor runs for.
    typealias Model = ScriptedAgentModel

    /// One step that gives output: the steps of ``ScriptedAgentStep``
    /// without the gate and the failure.
    private enum Output {
        /// Calls the tool `name` with `argumentsJSON`.
        case toolCall(name: String, argumentsJSON: String)

        /// Answers with the text.
        case finalText(String)
    }

    /// The token count of each emitted fragment. The scripted model meters
    /// nothing.
    private static let emittedTokenCount = 1

    /// Makes an executor. The configuration holds nothing that the executor
    /// reads: the script arrives with the model on each call.
    ///
    /// - Parameter configuration: The cache key.
    /// - Throws: Never. `throws` comes from the `LanguageModelExecutor`
    ///   requirement.
    init(configuration: Configuration) throws {}

    /// Records a new prompt, finds the play, waits on each gate before the
    /// next output step, and emits that step.
    ///
    /// - Parameters:
    ///   - request: The generation request with the full transcript.
    ///   - model: The model with the script.
    ///   - channel: The channel that the output goes into.
    /// - Throws: ``ScriptedAgentModelError`` when no play matches or the play
    ///   has no more output steps, `CancellationError` from a gate, or the
    ///   error of a ``ScriptedAgentStep/fail(_:)`` step.
    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: ScriptedAgentModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let transcript = request.transcript
        if case .prompt(let prompt) = transcript.last {
            model.script.record(prompt: ScriptedTranscriptText.text(of: prompt.segments))
        }
        let play = try model.script.play(
            instructions: ScriptedTranscriptText.instructions(of: transcript),
            firstPrompt: ScriptedTranscriptText.firstPrompt(of: transcript))
        let position = Self.outputCount(in: transcript)
        let step = try await Self.nextOutputStep(of: play, after: position)
        await Self.emit(step, position: position, into: channel)
    }

    /// The number of output steps that the transcript already holds: one for
    /// each `.toolCalls` entry and one for each `.response` entry.
    ///
    /// - Parameter transcript: The transcript of the generation call.
    /// - Returns: The count of played output steps.
    private static func outputCount(in transcript: Transcript) -> Int {
        transcript.count { entry in
            if case .toolCalls = entry { return true }
            if case .response = entry { return true }
            return false
        }
    }

    /// Waits on each gate after the played output steps, and gives the next
    /// output step.
    ///
    /// - Parameters:
    ///   - play: The play of the session.
    ///   - position: The count of played output steps.
    /// - Returns: The next output step.
    /// - Throws: ``ScriptedAgentModelError/playExhausted(key:)`` when the play
    ///   has no more output steps, `CancellationError` from a gate, or the
    ///   error of a ``ScriptedAgentStep/fail(_:)`` step.
    private static func nextOutputStep(
        of play: ScriptedAgentPlay, after position: Int
    ) async throws -> Output {
        var outputsSeen = 0
        for step in play.steps {
            let output: Output
            switch step {
            case .wait(let gate):
                if outputsSeen == position {
                    try await gate.wait()
                }
                continue
            case .fail(let error):
                if outputsSeen == position {
                    throw error
                }
                continue
            case .toolCall(let name, let argumentsJSON):
                output = .toolCall(name: name, argumentsJSON: argumentsJSON)
            case .finalText(let text):
                output = .finalText(text)
            }
            if outputsSeen == position { return output }
            outputsSeen += 1
        }
        throw ScriptedAgentModelError.playExhausted(key: play.key)
    }

    /// Emits one output step into `channel`.
    ///
    /// - Parameters:
    ///   - output: The output step.
    ///   - position: The position of the step, which makes the tool call id.
    ///   - channel: The channel that the output goes into.
    private static func emit(
        _ output: Output, position: Int, into channel: LanguageModelExecutorGenerationChannel
    ) async {
        switch output {
        case .toolCall(let name, let argumentsJSON):
            let callID = "scripted-call-\(position)"
            await channel.send(
                .toolCalls(
                    entryID: callID + "-entry",
                    action: .toolCall(
                        id: callID,
                        name: name,
                        action: .appendArguments(argumentsJSON, tokenCount: emittedTokenCount))))
        case .finalText(let text):
            await channel.send(.response(action: .appendText(text, tokenCount: emittedTokenCount)))
        }
    }
}

/// Reads the text of the transcript parts that select a play.
enum ScriptedTranscriptText {
    /// The text of the leading `.instructions` entry of `transcript`.
    ///
    /// - Parameter transcript: The transcript to read.
    /// - Returns: The text, or the empty string when there is no such entry.
    static func instructions(of transcript: Transcript) -> String {
        for entry in transcript {
            if case .instructions(let instructions) = entry {
                return text(of: instructions.segments)
            }
        }
        return ""
    }

    /// The text of the first `.prompt` entry of `transcript`.
    ///
    /// - Parameter transcript: The transcript to read.
    /// - Returns: The text, or the empty string when there is no such entry.
    static func firstPrompt(of transcript: Transcript) -> String {
        for entry in transcript {
            if case .prompt(let prompt) = entry {
                return text(of: prompt.segments)
            }
        }
        return ""
    }

    /// The joined text of `segments`.
    ///
    /// - Parameter segments: The segments to read.
    /// - Returns: The text of each segment, joined in order. A structured
    ///   segment gives its JSON. An attachment gives its description.
    static func text(of segments: [Transcript.Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text):
                text.content
            case .structure(let structure):
                structure.content.jsonString
            case .attachment:
                String(describing: segment)
            @unknown default:
                String(describing: segment)
            }
        }.joined()
    }
}
