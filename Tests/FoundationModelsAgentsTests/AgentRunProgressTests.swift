import Foundation
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing
import ULID

/// Pins the progress record of a run in operation (plan.md §9.1,
/// `check agent`): the text for each phase, the pass count, and the limits
/// of the tool names and of the text tail.
@Suite("Agent run progress")
struct AgentRunProgressTests {
    /// The id of the entry of each recorded-entry event.
    private static let entryID = "progress-entry"

    /// The name of the tool in the one-tool test.
    private static let toolName = "Read"

    /// The count of passes of one tool-calls entry and one response entry.
    private static let toolCallsAndResponsePasses = 2

    /// The count of tool names above the limit in the tool-name test.
    private static let extraToolNames = 2

    /// The count of characters above the limit in the text-tail test.
    private static let extraCharacters = 7

    /// The character that makes the long text of the text-tail test.
    private static let filler: Character = "x"

    /// The last characters of the long text of the text-tail test.
    private static let ending = "The end."

    /// The text of the answer of a turn.
    private static let answer = "The diff is correct."

    /// The text of an answer to a final message.
    private static let deliveredText = "Both agents finished."

    /// The session of each tool-invocation record.
    private static let sessionID = ULID()

    /// Gives the open live record of a call of the tool `name`.
    ///
    /// - Parameter name: The name of the tool.
    /// - Returns: The record.
    private static func openRecord(_ name: String) -> ToolInvocationRecord {
        ToolInvocationRecord(
            tool: name, op: name, correlationID: "run-\(name)", sessionID: sessionID, openedAt: Date())
    }

    /// Gives the event of a tool call that starts now.
    ///
    /// - Parameter name: The name of the tool.
    /// - Returns: The event of the open record.
    private static func toolOpened(_ name: String) -> SessionEvent {
        .toolInvocation(openRecord(name))
    }

    /// Gives the event of a tool call that returned.
    ///
    /// - Parameter name: The name of the tool.
    /// - Returns: The event of the closed record.
    private static func toolClosed(_ name: String) -> SessionEvent {
        .toolInvocation(openRecord(name).closed(at: Date()))
    }

    /// Gives a recorded-entry event.
    ///
    /// - Parameter kind: The kind of the entry.
    /// - Returns: The event.
    private static func entry(_ kind: RecordedEntryKind) -> SessionEvent {
        .entryRecorded(id: entryID, kind: kind)
    }

    /// Gives a record that applied `events` in order.
    ///
    /// - Parameter events: The events of the turn.
    /// - Returns: The record.
    private static func record(applying events: [SessionEvent]) -> AgentRunProgress {
        events.reduce(into: AgentRunProgress()) { progress, event in progress.apply(event) }
    }

    @Test("a new record tells the task turn, no passes, no tools, and no text")
    func newRecordTellsTaskTurn() {
        #expect(
            AgentRunProgress().text == """
                Phase: the task turn.
                Passes: 0.
                Last tools: none.
                Text so far: none.
                """)
    }

    @Test("the first line tells each phase")
    func firstLineTellsEachPhase() {
        var waiting = AgentRunProgress()
        waiting.phase = .waitingForChildren
        var answeringMail = AgentRunProgress()
        answeringMail.phase = .answeringMail

        #expect(waiting.text.hasPrefix("Phase: the wait for the agents that it started.\n"))
        #expect(answeringMail.text.hasPrefix("Phase: an answer to a final message.\n"))
    }

    @Test("an entry event adds no pass: the text tells the count that the run sets from its one counter")
    func textTellsPassesOfRunCounter() {
        var progress = Self.record(applying: [Self.entry(.toolCalls), Self.entry(.response)])
        let fromEvents = progress.passes
        progress.passes = Self.toolCallsAndResponsePasses

        #expect(fromEvents == 0)
        #expect(progress.text.contains("\nPasses: \(Self.toolCallsAndResponsePasses).\n"))
    }

    @Test("the record keeps only the newest tool names, up to the limit, in call order")
    func toolNamesStopAtLimit() {
        let names = (0..<(AgentRunProgress.toolNameLimit + Self.extraToolNames)).map { "tool-\($0)" }
        let progress = Self.record(applying: names.map(Self.toolOpened))
        let kept = Array(names.suffix(AgentRunProgress.toolNameLimit))

        #expect(progress.toolNames == kept)
        #expect(progress.text.contains("\nLast tools: \(kept.joined(separator: ", ")).\n"))
    }

    @Test("only an open tool record adds a name: its close and the recorded tool call of the diff add none")
    func onlyOpenRecordAddsName() {
        let progress = Self.record(applying: [
            Self.toolOpened(Self.toolName),
            Self.toolClosed(Self.toolName),
            .toolCall(id: Self.entryID, name: Self.toolName, argumentsJSON: "{}")
        ])

        #expect(progress.toolNames == [Self.toolName])
    }

    @Test("the text tail keeps the last characters up to the limit, and the text marks the cut")
    func textTailStopsAtLimit() {
        let fillerCount = AgentRunProgress.textTailLimit + Self.extraCharacters - Self.ending.count
        let long = String(repeating: Self.filler, count: fillerCount) + Self.ending
        let progress = Self.record(applying: [.textDelta(Self.answer), .textDelta(long)])
        let tail = String(long.suffix(AgentRunProgress.textTailLimit))

        #expect(progress.textTail == tail)
        #expect(progress.text.hasSuffix("\nText so far: ...\(tail)"))
    }

    @Test("text deltas add to the tail, and a text reset clears it")
    func textResetClearsTail() {
        let written = Self.record(applying: [.textDelta("The diff "), .textDelta("is correct.")])
        let reset = Self.record(applying: [.textDelta(Self.deliveredText), .textReset, .textDelta(Self.answer)])

        #expect(written.textTail == Self.answer)
        #expect(written.text.hasSuffix("\nText so far: \(Self.answer)"))
        #expect(reset.textTail == Self.answer)
    }

    @Test("the text of an answer to a final message replaces the tail")
    func deliveredTextReplacesTail() {
        var progress = Self.record(applying: [.textDelta(Self.answer)])
        progress.replaceText(with: Self.deliveredText)

        #expect(progress.textTail == Self.deliveredText)
        #expect(progress.text.hasSuffix("\nText so far: \(Self.deliveredText)"))
    }
}
