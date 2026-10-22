import Foundation
import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

/// Reads the recording of a Router session: the ``SessionRecord`` in the
/// frontmatter of its `index.md`, and its `transcript.jsonl`.
///
/// The router of ``LiveProfile`` records each session under
/// ``LiveProfile/recordingsDirectory``. A test reads the recording after the
/// turns that it examines have ended.
///
/// The Router writes each transcript event to the file before the call that
/// records it returns. Thus a transcript is complete when the session is
/// closed: after `close()` of a root session, and after `result()` of a run.
/// `result()` returns only after the run closed its session. The final
/// message of a run is in the transcript of its parent after the parent
/// answered that message as mail.
enum LiveRecording {
    /// The name of the transcript file in a session directory.
    private static let transcriptFileName = "transcript.jsonl"

    /// The words of the tool error that the Router adds to a prompt after it
    /// rejected a tool call: "Tool error: Your call to the tool "x" was
    /// rejected (reason), and no tool ran."
    private static let rejectedToolCallMarker = "was rejected ("

    /// Reads the record of a session directory with
    /// `RouterSessionDirectory.recordedSessions(in:)` of its recording root.
    ///
    /// - Parameter directory: The recording directory of the session.
    /// - Returns: The record of the session.
    /// - Throws: The error of `#require` when the recording root lists no
    ///   session of the directory, or the error of the read.
    static func session(in directory: URL) throws -> SessionRecord {
        let sessionId = directory.lastPathComponent
        return try #require(
            try RouterSessionDirectory.recordedSessions(in: directory.deletingLastPathComponent())
                .first { $0.sessionId.description == sessionId })
    }

    /// Reads the record of the session of a run.
    ///
    /// - Parameter run: A run that made a session.
    /// - Returns: The record of the session.
    /// - Throws: The error of `#require` when the run has no recording
    ///   directory, or the error of the read.
    static func session(of run: AgentRun) throws -> SessionRecord {
        try session(in: try #require(run.recordingDirectory))
    }

    /// Reads each event of the `transcript.jsonl` of a session directory, as
    /// the Router reads it: with `JSONLFile`, which decodes the millisecond
    /// ISO 8601 dates.
    ///
    /// - Parameter directory: The recording directory of the session.
    /// - Returns: The events, in file order.
    /// - Throws: The error of the read.
    static func events(in directory: URL) throws -> [TranscriptEvent] {
        try JSONLFile(url: directory.appendingPathComponent(transcriptFileName)).records(as: TranscriptEvent.self)
    }

    /// Gives the operation events that the entries of one kind carry.
    ///
    /// The Router writes each post two times: as a `.toolOutput` entry when
    /// the run posts it, and on the `.prompt` entry of the turn that reads
    /// it.
    ///
    /// - Parameters:
    ///   - kind: The kind of the entries, `.toolOutput` or `.prompt`.
    ///   - directory: The recording directory of the session.
    /// - Returns: The operation events, in file order.
    /// - Throws: The error of ``events(in:)``.
    static func operationEvents(of kind: TranscriptEvent.Kind, in directory: URL) throws -> [OperationEvent] {
        try events(in: directory).filter { $0.kind == kind }.flatMap(\.operationEvents)
    }

    /// Tells if the session read the post with `correlationID` before its
    /// final answer.
    ///
    /// The `.prompt` entry of a mail answer carries each final message that
    /// it gives: a `.completed` post. The final answer is the last `.response` entry that
    /// mirrors a transcript entry. The recorder gives each event a sequence
    /// number in the order of the log.
    ///
    /// - Parameters:
    ///   - correlationID: The correlation id of the post: the id of the tool
    ///     call that started the run that posted it.
    ///   - directory: The recording directory of the session.
    /// - Returns: `true` when a `.prompt` entry that carries the post comes
    ///   before the last `.response` entry. `false` when one of the two
    ///   entries is not in the transcript.
    /// - Throws: The error of ``events(in:)``.
    static func readsPost(_ correlationID: String, beforeFinalAnswerIn directory: URL) throws -> Bool {
        let events = try events(in: directory)
        let read = events.first { event in
            event.kind == .prompt
                && event.operationEvents.contains { $0.kind == .completed && $0.correlationID == correlationID }
        }
        let answer = events.last { $0.kind == .response && $0.mirrorsTranscriptEntry }
        if let read, let answer {
            return read.seq < answer.seq
        }
        return false
    }

    /// Gives the text of each prompt that tells the model that the Router
    /// rejected one of its tool calls.
    ///
    /// The parser records no `.toolCalls` entry for a rejected call. The
    /// Router sends the prompt again with a tool error after it, and the
    /// transcript records that prompt. The tool error names the reason, for
    /// example `undeclared_tool` for a call of a tool that the session does
    /// not have.
    ///
    /// - Parameter directory: The recording directory of the session.
    /// - Returns: The text of each such `.prompt` entry, in file order.
    /// - Throws: The error of ``events(in:)``.
    static func rejectedToolCallPrompts(in directory: URL) throws -> [String] {
        try events(in: directory)
            .filter { $0.kind == .prompt }
            .compactMap(\.text)
            .filter { $0.contains(rejectedToolCallMarker) }
    }

    /// Gives the text of each tool answer that the session recorded. A post
    /// is not a tool answer, thus an entry that carries operation events is
    /// not in the result.
    ///
    /// - Parameter directory: The recording directory of the session.
    /// - Returns: The text segments of each `.toolOutput` entry, joined, in
    ///   file order.
    /// - Throws: The error of ``events(in:)``.
    static func toolAnswers(in directory: URL) throws -> [String] {
        try events(in: directory)
            .filter { $0.kind == .toolOutput && $0.operationEvents.isEmpty }
            .map { event in (event.entry?.segments ?? []).lazy.map(text(of:)).joined() }
    }

    /// Gives the text of one segment.
    ///
    /// - Parameter segment: A segment of a recorded entry.
    /// - Returns: The content of a text segment, the JSON of a structured
    ///   segment, or an empty text for each other segment.
    private static func text(of segment: SegmentPayload) -> String {
        switch segment {
        case .text(_, let content):
            content
        case .structure(_, _, let contentJSON), .custom(_, _, let contentJSON, _):
            contentJSON
        case .attachment, .unknown:
            ""
        }
    }
}
