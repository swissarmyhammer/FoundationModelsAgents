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
    /// The receiver of each line that a mode writes in a case. The receiver
    /// sends a line or ends the input.
    private protocol LineReading {
        /// Tells the receiver that the mode wrote a line.
        ///
        /// - Parameters:
        ///   - written: All the lines that the mode wrote so far, in order.
        ///   - input: The input of the mode.
        func didWrite(_ written: [String], input: AgentsDemoInput.Continuation) async
    }

    /// The mode of `agents-demo` that a case runs.
    private enum ProfileMode {
        /// The `--chat` mode.
        case chat

        /// The `--fan-out` mode.
        case fanOut

        /// Runs the mode over the fixture library.
        ///
        /// - Parameters:
        ///   - profile: The resolved profile.
        ///   - workingDirectory: The working directory of the runs.
        ///   - input: The lines that the user types.
        ///   - output: The receiver of each line.
        /// - Throws: The error of the mode.
        func run(
            profile: LanguageModelProfile, workingDirectory: URL, input: AgentsDemoInput,
            output: @escaping AgentsDemoOutput
        ) async throws {
            let registry = AgentRegistry(stack: FixtureLibrary.stack())
            // The cases read the mail flow, thus each run goes to the background at once.
            switch self {
            case .chat:
                try await AgentsDemoModes.chat(
                    profile: profile, registry: registry, workingDirectory: workingDirectory,
                    input: input, output: output,
                    inlineSettleGrace: AgentRunHarness.settleGrace)
            case .fanOut:
                try await AgentsDemoModes.fanOut(
                    profile: profile, registry: registry, workingDirectory: workingDirectory,
                    input: input, output: output,
                    inlineSettleGrace: AgentRunHarness.settleGrace)
            }
        }
    }

    /// What a mode wrote in a case, and the slots that its sessions used.
    private struct ModeRecord {
        /// The lines that the mode wrote, in order.
        let written: [String]

        /// The slot of each Router session that recorded.
        let slots: [ModelSlot]
    }

    /// Ends the input when the lines have a `runSettled` line and the root
    /// answer to the mail of the lead run.
    private struct SettledMailReader: LineReading {
        func didWrite(_ written: [String], input: AgentsDemoInput.Continuation) async {
            let settled = written.contains { $0.hasPrefix(AgentsDemoModes.settledPrefix) }
            if settled && written.contains(AgentsDemoModes.rootLine(AgentsDemoProfileModeTests.deliveredText)) {
                input.finish()
            }
        }
    }

    /// Sends ``userLine`` after the first root answer, and ends the input
    /// after the answer to ``userLine``.
    private struct UserLineReader: LineReading {
        func didWrite(_ written: [String], input: AgentsDemoInput.Continuation) async {
            if written.last == AgentsDemoModes.rootLine(AgentsDemoProfileModeTests.rootText) {
                input.yield(AgentsDemoProfileModeTests.userLine)
            }
            if written.last == AgentsDemoModes.rootLine(AgentsDemoProfileModeTests.userAnswer) {
                input.finish()
            }
        }
    }

    /// Ends the input after the root answer to the mail, when the gated run
    /// waits on its gate.
    private struct GatedRunReader: LineReading {
        /// The gate that the late run waits on.
        let gate: ScriptedGate

        func didWrite(_ written: [String], input: AgentsDemoInput.Continuation) async {
            if written.last == AgentsDemoModes.rootLine(AgentsDemoProfileModeTests.deliveredText) {
                await gate.waitForArrival()
                input.finish()
            }
        }
    }

    /// Ends the input when a root answer holds the text of each fan-out run.
    private struct FanOutAnswerReader: LineReading {
        func didWrite(_ written: [String], input: AgentsDemoInput.Continuation) async {
            let answer = written.last { $0.hasPrefix(AgentsDemoModes.rootPrefix) }
            if let answer,
                answer.contains(AgentsDemoProfileModeTests.reviewerText),
                answer.contains(AgentsDemoProfileModeTests.testWriterText) {
                input.finish()
            }
        }
    }

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

        let written = try await Self.run(.chat, script: script, reader: SettledMailReader()).written
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

        let written = try await Self.run(.chat, script: script, reader: UserLineReader()).written

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

        let written = try await Self.run(.chat, script: script, reader: GatedRunReader(gate: gate)).written
        let cancelledLine = AgentsDemoModes.runLine(
            agent: AgentsDemoModes.reviewerAgent, status: AgentsDemoModes.status(of: .cancelled), level: 0)

        #expect(written.contains(cancelledLine))
        #expect(!written.contains { $0.contains(Self.lateReviewerText) })
    }

    @Test("the fan-out mode writes the mail answer and one result from each generation slot",
        .timeLimit(.minutes(1)))
    func fanOutModeWritesOneResultFromEachSlot() async throws {
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

        let record = try await Self.run(.fanOut, script: script, reader: FanOutAnswerReader())

        #expect(record.written.contains(AgentsDemoModes.fanOutLine(
            agent: AgentsDemoModes.reviewerAgent, model: ModelSlot.flash.rawValue, text: Self.reviewerText)))
        #expect(record.written.contains(AgentsDemoModes.fanOutLine(
            agent: AgentsDemoModes.testWriterAgent, model: ModelSlot.standard.rawValue, text: Self.testWriterText)))
        #expect(Set(record.slots.map(\.rawValue)) == Set([ModelSlot.flash, ModelSlot.standard].map(\.rawValue)))
    }

    // MARK: - Helpers

    /// Runs `mode` over the fixture library with a scripted profile that
    /// plays `script`, in a temporary recordings folder and a temporary
    /// working directory.
    ///
    /// - Parameters:
    ///   - mode: The mode to run.
    ///   - script: The script of each generation slot.
    ///   - reader: The receiver of each line. It must end the input.
    /// - Returns: The lines that the mode wrote, and the slot of each session
    ///   that recorded.
    /// - Throws: The error of the profile, of the file system, or of the mode.
    private static func run(
        _ mode: ProfileMode, script: ScriptedAgentScript, reader: some LineReading
    ) async throws -> ModeRecord {
        let recordings = try TemporaryLayer.makeEmpty()
        defer { try? recordings.delete() }
        let workingDirectory = try TemporaryLayer.makeEmpty()
        defer { try? workingDirectory.delete() }
        let (router, profile) = try await ScriptedProfile.make(script: script, recordingsDir: recordings.root)
        let written = try await conversation(
            mode: mode, profile: profile, workingDirectory: workingDirectory.root, reader: reader)
        let slots = try recordedSlots(in: recordings.root)
        withExtendedLifetime(router) {}
        return ModeRecord(written: written, slots: slots)
    }

    /// Runs a mode with an input stream, and gives each line that it writes
    /// to `reader`.
    ///
    /// - Parameters:
    ///   - mode: The mode to run.
    ///   - profile: The resolved profile.
    ///   - workingDirectory: The working directory of the runs.
    ///   - reader: The receiver of each line. It must end the input, else the
    ///     mode does not end.
    /// - Returns: The lines that the mode wrote, in order.
    /// - Throws: The error of the mode.
    private static func conversation(
        mode: ProfileMode, profile: LanguageModelProfile, workingDirectory: URL, reader: some LineReading
    ) async throws -> [String] {
        let (input, inputContinuation) = AgentsDemoInput.makeStream()
        let (lines, linesContinuation) = AsyncStream.makeStream(of: String.self)
        let run = Task {
            defer { linesContinuation.finish() }
            try await mode.run(profile: profile, workingDirectory: workingDirectory, input: input) {
                linesContinuation.yield($0)
            }
        }
        var written: [String] = []
        for await line in lines {
            written.append(line)
            await reader.didWrite(written, input: inputContinuation)
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
