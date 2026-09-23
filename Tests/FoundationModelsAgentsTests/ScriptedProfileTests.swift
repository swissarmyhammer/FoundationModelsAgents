import FoundationModels
import FoundationModelsRouter
import Synchronization
import Testing

/// Makes sure that the scripted profile of the test support runs a real
/// `RoutedSession` turn with no real model.
///
/// Each test resolves its own profile through `ScriptedProfile.make`, thus
/// each test has its own router, its own model pool, and its own script.
@Suite("Scripted profile")
struct ScriptedProfileTests {
    /// The key that selects the play of each test by the first prompt.
    private static let promptKey = "scripted-prompt"

    /// The final text that each play gives.
    private static let finalText = "scripted final text"

    /// The text that the scripted tool call sends to the note tool.
    private static let noteText = "alpha"

    /// A flash session gives the final text of the script, and the model
    /// records the prompt that it got.
    @Test("A flash session turn gives the scripted final text")
    func flashTurnGivesScriptedFinalText() async throws {
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(key: Self.promptKey, steps: [.finalText(Self.finalText)])
        ])
        let (_, profile) = try await ScriptedProfile.make(script: script)

        let session = profile.flash.makeSession(instructions: "You are a scripted agent.")
        let answer = try await session.respond(to: Self.promptKey)

        #expect(answer == Self.finalText)
        #expect(script.prompts == [Self.promptKey])
    }

    /// A play can also be selected by the session instructions.
    @Test("The session instructions select a play")
    func instructionsSelectAPlay() async throws {
        let instructionsKey = "scripted-instructions"
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(key: Self.promptKey, steps: [.finalText("the prompt play")]),
            ScriptedAgentPlay(key: instructionsKey, steps: [.finalText(Self.finalText)])
        ])
        let (_, profile) = try await ScriptedProfile.make(script: script)

        let session = profile.standard.makeSession(instructions: "Agent \(instructionsKey).")
        let answer = try await session.respond(to: "a prompt with no key")

        #expect(answer == Self.finalText)
    }

    /// A scripted tool call runs the mounted tool, and the tool output is in
    /// the transcript of the session.
    @Test("A scripted step calls a mounted tool")
    func scriptedStepCallsMountedTool() async throws {
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: Self.promptKey,
                steps: [
                    .toolCall(name: NoteTool.toolName, argumentsJSON: #"{"text":"\#(Self.noteText)"}"#),
                    .finalText(Self.finalText)
                ])
        ])
        let (_, profile) = try await ScriptedProfile.make(script: script)

        let session = profile.flash.makeSession(tools: [NoteTool()])
        let answer = try await session.respond(to: Self.promptKey)
        let outputs = Self.toolOutputTexts(in: await session.transcript, toolName: NoteTool.toolName)

        #expect(answer == Self.finalText)
        #expect(outputs.count == 1)
        #expect(outputs.first?.contains(NoteTool.output(for: Self.noteText)) == true)
    }

    /// A gated step holds the turn until the test opens the gate.
    @Test("A gated step blocks the turn until the gate opens")
    func gatedStepBlocksTurnUntilGateOpens() async throws {
        let gate = ScriptedGate()
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(key: Self.promptKey, steps: [.wait(gate), .finalText(Self.finalText)])
        ])
        let (_, profile) = try await ScriptedProfile.make(script: script)
        let session = profile.flash.makeSession()
        let finished = TurnFlag()

        let turn = Task {
            let answer = try await session.respond(to: Self.promptKey)
            finished.set()
            return answer
        }
        await gate.waitForArrival()

        #expect(!finished.isSet)
        gate.open()
        #expect(try await turn.value == Self.finalText)
        #expect(finished.isSet)
    }

    /// The standard slot and the flash slot resolve to two different models.
    @Test("The two slots have different chosen models")
    func slotsHaveDifferentChosenModels() async throws {
        let (_, profile) = try await ScriptedProfile.make(script: ScriptedAgentScript([]))

        #expect(profile.standard.chosen.stringValue != profile.flash.chosen.stringValue)
    }

    /// The text of each `.toolOutput` entry of `toolName` in `transcript`.
    ///
    /// - Parameters:
    ///   - transcript: The transcript to read.
    ///   - toolName: The name of the tool whose outputs to read.
    /// - Returns: One string for each output entry, in transcript order.
    private static func toolOutputTexts(in transcript: Transcript, toolName: String) -> [String] {
        transcript.compactMap { entry -> String? in
            if case .toolOutput(let output) = entry, output.toolName == toolName {
                return ScriptedTranscriptText.text(of: output.segments)
            }
            return nil
        }
    }
}

/// A tool that answers with a fixed prefix and the text it got.
private struct NoteTool: Tool {
    /// The name that a scripted step calls the tool by.
    static let toolName = "note"

    /// The arguments of the tool.
    @Generable
    struct Arguments {
        /// The text to note.
        let text: String
    }

    let name = NoteTool.toolName

    let description = "Notes a text."

    /// The output of the tool for `text`.
    ///
    /// - Parameter text: The text that the tool got.
    /// - Returns: The text with the fixed prefix.
    static func output(for text: String) -> String {
        "noted: \(text)"
    }

    func call(arguments: Arguments) async throws -> String {
        Self.output(for: arguments.text)
    }
}

/// A flag that a turn task sets when the turn returns.
private final class TurnFlag: Sendable {
    /// The value of the flag.
    private let value = Mutex(false)

    /// `true` after ``set()``.
    var isSet: Bool { value.withLock { $0 } }

    /// Sets the flag.
    func set() {
        value.withLock { $0 = true }
    }
}
