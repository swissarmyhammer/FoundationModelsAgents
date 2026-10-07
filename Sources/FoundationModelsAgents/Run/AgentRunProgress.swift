import FoundationModelsRouter

/// The live progress of a run in operation, as `check agent` tells it
/// (plan.md §9.1).
///
/// The run feeds the record from the one session-event subscription of the
/// run. The answer of the task prompt streams its text, thus its text
/// deltas feed the tail while it runs. An answer to mail streams no text,
/// thus the tail of that answer comes from its reply when it ends.
///
/// The pass count is not an event count of the record: the run sets
/// ``passes`` from its one counter, ``AgentRunTurns``, when it gives the
/// record.
///
/// The record never reads the transcript. Thus a read of the record never
/// waits for the turn.
struct AgentRunProgress: Sendable, Equatable {
    /// The last message of one running child, as the last event of that
    /// child.
    struct ChildMessage: Sendable, Equatable {
        /// The completion token of the `start agent` call of the child.
        let token: String

        /// The first line of the text of the message.
        let firstLine: String

        /// The line of the text of the record: "Last event of `token`:
        /// message: `firstLine`".
        var line: String {
            "Last event of \(token): message: \(firstLine)"
        }
    }

    /// The most tool names that the record keeps.
    static let toolNameLimit = 5

    /// The most characters of the text tail that the record keeps.
    static let textTailLimit = 240

    /// The mark before a text tail that the record cut.
    static let cutMark = "..."

    /// The word that the text gives for an empty list or an empty tail.
    static let none = "none"

    /// The part of the life of the run after its setup.
    var phase = AgentRunPhase.taskTurn

    /// The count of passes of the control loop over all the turns so far.
    /// The run sets it from ``AgentRunTurns/count``.
    var passes = 0

    /// The names of the newest tool calls, oldest first, at most
    /// ``toolNameLimit``.
    private(set) var toolNames: [String] = []

    /// The last characters of the text of the current turn, at most
    /// ``textTailLimit``.
    private(set) var textTail = ""

    /// `true` when the text of the current turn has more characters than
    /// ``textTail``.
    private var isCut = false

    /// The last message of each running child that sent a message, in the
    /// order of the first message of each child.
    private(set) var childMessages: [ChildMessage] = []

    /// The lines that tell the record: the phase, the pass count, the last
    /// tool names, the last message of each running child, and the text so
    /// far.
    var text: String {
        let tools = toolNames.isEmpty ? Self.none : toolNames.joined(separator: ", ")
        let tail = textTail.isEmpty ? "\(Self.none)." : (isCut ? Self.cutMark : "") + textTail
        let lines = ["Phase: \(phaseName).", "Passes: \(passes).", "Last tools: \(tools)."]
            + childMessages.map(\.line) + ["Text so far: \(tail)"]
        return lines.joined(separator: "\n")
    }

    /// The name of ``phase`` in the text.
    private var phaseName: String {
        switch phase {
        case .taskTurn:
            "the task turn"
        case .waitingForChildren:
            "the wait for the agents that it started"
        case .answeringMail:
            "an answer to a final message"
        }
    }

    /// Applies one event of the session.
    ///
    /// The open live record of a tool call adds the name of the tool. The
    /// Router sends that record when the call starts, while the submission
    /// runs. The `toolCall` event of the same call comes from the transcript
    /// diff when the submission ends, thus it adds no name a second time. A
    /// text delta adds to the tail, and a text reset clears it. The end of an
    /// answer puts its reply in the tail. A message of a child is the last
    /// event of that child (``record(childMessage:)``), and the settlement of
    /// a child removes that event: the child does not run now.
    /// `SessionEvent` has no library evolution, thus each other event
    /// changes nothing. A pass entry also changes nothing: ``AgentRunTurns``
    /// counts the passes.
    ///
    /// - Parameter event: The event.
    mutating func apply(_ event: SessionEvent) {
        if case .toolInvocation(let record) = event, record.closedAt == nil {
            toolNames = Array((toolNames + [record.tool]).suffix(Self.toolNameLimit))
        }
        if case .textDelta(let fragment) = event {
            replaceText(with: textTail + fragment, cut: isCut)
        }
        if case .textReset = event {
            replaceText(with: "")
        }
        if case .answered(let answer) = event {
            replaceText(with: answer.reply)
        }
        if case .runMessage(let message) = event {
            record(childMessage: message)
        }
        if case .runSettled(let terminal) = event {
            childMessages.removeAll { $0.token == terminal.correlationID }
        }
    }

    /// Keeps the first line of `message` as the last event of its child. A
    /// child that sent a message before keeps its place in the list.
    ///
    /// - Parameter message: The message of a child.
    private mutating func record(childMessage message: OperationEvent) {
        let firstLine = message.detail.prefix { !$0.isNewline }
        let line = ChildMessage(token: message.correlationID, firstLine: String(firstLine))
        if let index = childMessages.firstIndex(where: { $0.token == line.token }) {
            childMessages[index] = line
        } else {
            childMessages.append(line)
        }
    }

    /// Replaces the text so far with `text`, for example with the reply of
    /// an answer.
    ///
    /// - Parameter text: The full text of the turn.
    mutating func replaceText(with text: String) {
        replaceText(with: text, cut: false)
    }

    /// Keeps the last ``textTailLimit`` characters of `text` as the tail.
    ///
    /// - Parameters:
    ///   - text: The text to keep the tail of.
    ///   - cut: `true` when the record already cut the text before `text`.
    private mutating func replaceText(with text: String, cut: Bool) {
        textTail = String(text.suffix(Self.textTailLimit))
        isCut = cut || text.count > Self.textTailLimit
    }
}
