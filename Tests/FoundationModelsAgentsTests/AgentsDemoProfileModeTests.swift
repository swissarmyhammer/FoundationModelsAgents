import Foundation
import FoundationModelsAgents
import FoundationModelsRouter
import Testing

@testable import agents_demo

/// The contract of the two modes of `agents-demo` that need a resolved
/// profile: `--chat` and `--fan-out` (plan.md §12, §13).
///
/// Each case gives a scripted profile and an input stream to the function of
/// the mode. The mode sends the first prompt and each input line to the root
/// session, and writes each answer that the session events give, also the
/// answers that the mail of the runs starts. The mode calls no driver method
/// and does not wait for the runs: it ends when its input ends. Thus each case
/// ends the input only after it read the lines that it checks.
///
/// The root session and the `lead` run are on the `standard` slot.
/// code-reviewer runs on the `flash` slot.
@Suite("agents-demo with a profile")
struct AgentsDemoProfileModeTests {
    /// The receiver of each line that a mode writes in a case: all the lines
    /// so far, and the input of the mode. The receiver sends a line or ends
    /// the input.
    typealias Reader = ([String], AsyncStream<String>.Continuation) async -> Void

    /// The prompt that the root session gives to the `lead` run.
    private static let leadKey = "demo-lead-key: divide the task"

    /// The prompt that the lead gives to the code-reviewer child.
    private static let reviewerKey = "demo-reviewer-key: review the parser"

    /// The prompt that the lead gives to the test-writer child.
    private static let testWriterKey = "demo-test-writer-key: test the parser"

    /// The prompt of the code-reviewer run that the root session starts in
    /// its answer to the mail. The run waits on a gate that never opens.
    private static let lateReviewerKey = "demo-late-key: review the parser again"

    /// The final text of the code-reviewer runs.
    private static let reviewerText = "The parser is correct."

    /// The final text of the test-writer runs.
    private static let testWriterText = "The tests of the parser pass."

    /// The text that the gated run gives when its gate opens.
    private static let lateReviewerText = "The parser is still correct."

    /// The answer of the root session to the first prompt.
    private static let rootText = "I started the lead agent."

    /// The answer of the root session to the mail of the lead run.
    private static let deliveredText = "The lead agent finished."

    /// A line that the user types.
    private static let userLine = "demo-user-key: what is the state?"

    /// The answer of the root session to ``userLine``.
    private static let userAnswer = "The work goes on."

    /// The file that each Router session writes in its recording directory.
    private static let sidecarName = "session.json"

    @Test("the chat mode writes the answer that the mail of lead starts, with no user input", .timeLimit(.minutes(1)))
    func chatModeWritesTheAnswerToTheMail() async throws {
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: AgentsDemoModes.chatInstructions,
                steps: [
                    NestedRunTests.startStep(AgentsDemoModes.leadAgent, prompt: Self.leadKey),
                    .finalText(Self.rootText),
                    .finalText(Self.deliveredText)
                ]),
            NestedRunTests.parentPlay(
                Self.leadKey,
                children: [
                    (AgentsDemoModes.reviewerAgent, Self.reviewerKey),
                    (AgentsDemoModes.testWriterAgent, Self.testWriterKey)
                ]),
            ScriptedAgentPlay(key: Self.reviewerKey, steps: [.finalText(Self.reviewerText)]),
            ScriptedAgentPlay(key: Self.testWriterKey, steps: [.finalText(Self.testWriterText)])
        ])

        let written = try await Self.chatLines(script: script) { written, input in
            let settled = written.contains { $0.hasPrefix(AgentsDemoModes.settledPrefix) }
            if settled && written.contains(AgentsDemoModes.rootLine(Self.deliveredText)) {
                input.finish()
            }
        }
        let leadPrefix = AgentsDemoModes.runLine(agent: AgentsDemoModes.leadAgent, status: "", level: 0)
        let leadLine = try #require(written.first { $0.hasPrefix(leadPrefix) })

        #expect(written.contains(AgentsDemoModes.rootLine(Self.rootText)))
        #expect(written.filter { $0.hasPrefix(AgentsDemoModes.settledPrefix) }.count == 1)
        #expect(written.contains(
            AgentsDemoModes.runLine(agent: AgentsDemoModes.reviewerAgent, status: Self.reviewerText, level: 1)))
        #expect(written.contains(
            AgentsDemoModes.runLine(agent: AgentsDemoModes.testWriterAgent, status: Self.testWriterText, level: 1)))
        #expect(leadLine.contains(Self.reviewerText))
        #expect(leadLine.contains(Self.testWriterText))
    }

    @Test("the chat mode sends each input line to the root session and writes its answer", .timeLimit(.minutes(1)))
    func chatModeSendsEachInputLine() async throws {
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: AgentsDemoModes.chatInstructions,
                steps: [.finalText(Self.rootText), .finalText(Self.userAnswer)])
        ])

        let written = try await Self.chatLines(script: script) { written, input in
            if written.last == AgentsDemoModes.rootLine(Self.rootText) {
                input.yield(Self.userLine)
            }
            if written.last == AgentsDemoModes.rootLine(Self.userAnswer) {
                input.finish()
            }
        }

        #expect(written == [AgentsDemoModes.rootLine(Self.rootText), AgentsDemoModes.rootLine(Self.userAnswer)])
    }

    @Test("the chat mode cancels the open runs of the root session before it closes the session",
        .timeLimit(.minutes(1)))
    func chatModeCancelsOpenRunsBeforeClose() async throws {
        let gate = ScriptedGate()
        defer { gate.open() }
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: AgentsDemoModes.chatInstructions,
                steps: [
                    NestedRunTests.startStep(AgentsDemoModes.leadAgent, prompt: Self.leadKey),
                    .finalText(Self.rootText),
                    NestedRunTests.startStep(AgentsDemoModes.reviewerAgent, prompt: Self.lateReviewerKey),
                    .finalText(Self.deliveredText)
                ]),
            NestedRunTests.parentPlay(Self.leadKey, children: [(AgentsDemoModes.reviewerAgent, Self.reviewerKey)]),
            ScriptedAgentPlay(key: Self.reviewerKey, steps: [.finalText(Self.reviewerText)]),
            ScriptedAgentPlay(key: Self.lateReviewerKey, steps: [.wait(gate), .finalText(Self.lateReviewerText)])
        ])

        let written = try await Self.chatLines(script: script) { written, input in
            if written.last == AgentsDemoModes.rootLine(Self.deliveredText) {
                await gate.waitForArrival()
                input.finish()
            }
        }
        let cancelledLine = AgentsDemoModes.runLine(
            agent: AgentsDemoModes.reviewerAgent, status: AgentsDemoModes.status(of: .cancelled), level: 0)

        #expect(written.contains(cancelledLine))
        #expect(!written.contains { $0.contains(Self.lateReviewerText) })
    }

    @Test("the fan-out mode writes the mail answer and one result from each generation slot",
        .timeLimit(.minutes(1)))
    func fanOutModeWritesOneResultFromEachSlot() async throws {
        let recordings = try TemporaryLayer.makeEmpty()
        defer { try? recordings.delete() }
        let workingDirectory = try TemporaryLayer.makeEmpty()
        defer { try? workingDirectory.delete() }
        let script = ScriptedAgentScript([
            NestedRunTests.parentPlay(
                AgentsDemoModes.fanOutInstructions,
                children: [
                    (AgentsDemoModes.reviewerAgent, AgentsDemoModes.reviewerPrompt),
                    (AgentsDemoModes.testWriterAgent, AgentsDemoModes.testWriterPrompt)
                ]),
            ScriptedAgentPlay(key: AgentsDemoModes.reviewerPrompt, steps: [.finalText(Self.reviewerText)]),
            ScriptedAgentPlay(key: AgentsDemoModes.testWriterPrompt, steps: [.finalText(Self.testWriterText)])
        ])
        let (router, profile) = try await ScriptedProfile.make(script: script, recordingsDir: recordings.root)

        let written = try await Self.conversation(
            mode: { input, output in
                try await AgentsDemoModes.fanOut(
                    profile: profile, registry: AgentRegistry(stack: FixtureLibrary.stack()),
                    workingDirectory: workingDirectory.root, input: input, output: output)
            },
            reader: { written, input in
                let answer = written.last { $0.hasPrefix(AgentsDemoModes.rootPrefix) }
                if let answer, answer.contains(Self.reviewerText), answer.contains(Self.testWriterText) {
                    input.finish()
                }
            })
        let slots = try Self.recordedSlots(in: recordings.root)
        withExtendedLifetime(router) {}

        #expect(written.contains(AgentsDemoModes.fanOutLine(
            agent: AgentsDemoModes.reviewerAgent, model: ModelSlot.flash.rawValue, text: Self.reviewerText)))
        #expect(written.contains(AgentsDemoModes.fanOutLine(
            agent: AgentsDemoModes.testWriterAgent, model: ModelSlot.standard.rawValue, text: Self.testWriterText)))
        #expect(Set(slots.map(\.rawValue)) == Set([ModelSlot.flash, ModelSlot.standard].map(\.rawValue)))
    }

    // MARK: - Helpers

    /// Runs the chat mode over the fixture library with a scripted profile
    /// that plays `script`.
    ///
    /// - Parameters:
    ///   - script: The script of each generation slot.
    ///   - reader: The receiver of each line. It must end the input.
    /// - Returns: The lines that the mode wrote, in order.
    /// - Throws: The error of the profile, of the file system, or of the mode.
    private static func chatLines(script: ScriptedAgentScript, reader: Reader) async throws -> [String] {
        let recordings = try TemporaryLayer.makeEmpty()
        defer { try? recordings.delete() }
        let workingDirectory = try TemporaryLayer.makeEmpty()
        defer { try? workingDirectory.delete() }
        let (router, profile) = try await ScriptedProfile.make(script: script, recordingsDir: recordings.root)
        let written = try await conversation(
            mode: { input, output in
                try await AgentsDemoModes.chat(
                    profile: profile, registry: AgentRegistry(stack: FixtureLibrary.stack()),
                    workingDirectory: workingDirectory.root, input: input, output: output)
            },
            reader: reader)
        withExtendedLifetime(router) {}
        return written
    }

    /// Runs a mode with an input stream, and gives each line that it writes
    /// to `reader`.
    ///
    /// - Parameters:
    ///   - mode: The work of the mode, over the input and the output.
    ///   - reader: The receiver of each line. It must end the input, else the
    ///     mode does not end.
    /// - Returns: The lines that the mode wrote, in order.
    /// - Throws: The error of the mode.
    private static func conversation(
        mode: @escaping @Sendable (AgentsDemoInput, @escaping AgentsDemoOutput) async throws -> Void,
        reader: Reader
    ) async throws -> [String] {
        let (input, inputContinuation) = AsyncStream.makeStream(of: String.self)
        let (lines, linesContinuation) = AsyncStream.makeStream(of: String.self)
        let run = Task {
            defer { linesContinuation.finish() }
            try await mode(input) { linesContinuation.yield($0) }
        }
        var written: [String] = []
        for await line in lines {
            written.append(line)
            await reader(written, inputContinuation)
        }
        try await run.value
        return written
    }

    /// Reads the slot of each Router session that recorded under `directory`.
    ///
    /// - Parameter directory: The recordings root of the router.
    /// - Returns: The slot of each `session.json` under the folder.
    /// - Throws: The error of `#require`, of the read, or of the decode.
    private static func recordedSlots(in directory: URL) throws -> [ModelSlot] {
        let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        return try files.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == sidecarName }
            .map { try RecordedSidecar.read(in: $0.deletingLastPathComponent()).slot }
    }
}

/// The contract of the line that the chat and fan-out modes write for each
/// event of the root session.
@Suite("agents-demo event lines")
struct AgentsDemoEventLineTests {
    /// The answer text of the answered case.
    private static let reply = "The review is done."

    /// The error text of the failed case.
    private static let errorText = "the model failed"

    /// The mail-only answer limit of the paused case.
    private static let mailOnlyAnswerLimit = 3

    @Test("an answer gives one root line with its reply")
    func answerGivesARootLine() {
        let answer = SessionAnswer(
            reply: Self.reply, messageIds: [], usage: nil, compactions: [], toolCalls: [], toolInvocations: [])

        #expect(AgentsDemoModes.lines(for: .answered(answer)) == [AgentsDemoModes.rootLine(Self.reply)])
    }

    @Test("a failed answer gives one line with the reason")
    func failedAnswerGivesTheReason() {
        let failed = AnswerFailure(messageIds: [], reason: .error(Self.errorText))
        let cancelled = AnswerFailure(messageIds: [], reason: .cancelled)

        #expect(AgentsDemoModes.lines(for: .answerFailed(failed)) == [AgentsDemoModes.failedPrefix + Self.errorText])
        #expect(AgentsDemoModes.lines(for: .answerFailed(cancelled))
            == [AgentsDemoModes.failedPrefix + AgentsDemoModes.cancelledText])
    }

    @Test("a mail delivery pause gives the pause and tells the user to send a message")
    func mailDeliveryPauseTellsTheUserToSendAMessage() {
        let pause = MailDeliveryPause(limit: Self.mailOnlyAnswerLimit, heldMail: [])

        #expect(AgentsDemoModes.lines(for: .mailDeliveryPaused(pause))
            == [AgentsDemoModes.pausedPrefix + pause.description, AgentsDemoModes.sendMessageHint])
    }

    @Test("a text fragment gives no line, because the answer event holds the whole reply")
    func textDeltaGivesNoLine() {
        #expect(AgentsDemoModes.lines(for: .textDelta(Self.reply)).isEmpty)
    }
}
