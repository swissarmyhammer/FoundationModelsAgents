import Foundation
import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

/// The parts of the `session.json` of a Router session that the live suites
/// read.
///
/// The fields of `SessionSidecar` are internal to the Router, thus the suites
/// decode the file into this subset.
struct LiveSessionRecord: Decodable {
    /// The parts of the configuration of the session.
    struct Configuration: Decodable {
        /// The instructions of the session.
        let instructions: String?
    }

    /// The slot of the session.
    let slot: ModelSlot

    /// The lineage record of the session, or `nil` for a session that no
    /// tool call started.
    let agentSpawn: SessionSidecar.AgentSpawn?

    /// The configuration of the session.
    let configuration: Configuration
}

/// Reads the recording of a Router session: its `session.json` and its
/// `transcript.jsonl`.
///
/// The router of ``LiveProfile`` records each session under
/// ``LiveProfile/recordingsDirectory``. A test reads the recording after the
/// turns that it examines have ended.
enum LiveRecording {
    /// The name of the sidecar file in a session directory.
    private static let sessionFileName = "session.json"

    /// The name of the transcript file in a session directory.
    private static let transcriptFileName = "transcript.jsonl"

    /// Reads the `session.json` of a session directory.
    ///
    /// - Parameter directory: The recording directory of the session.
    /// - Returns: The decoded parts of the file.
    /// - Throws: The error of the read or of the decode.
    static func session(in directory: URL) throws -> LiveSessionRecord {
        try JSONDecoder().decode(
            LiveSessionRecord.self, from: Data(contentsOf: directory.appendingPathComponent(sessionFileName)))
    }

    /// Reads the `session.json` of the session of a run.
    ///
    /// - Parameter run: A run that made a session.
    /// - Returns: The decoded parts of the file.
    /// - Throws: The error of `#require` when the run has no recording
    ///   directory, or the error of the read.
    static func session(of run: AgentRun) throws -> LiveSessionRecord {
        try session(in: try #require(run.recordingDirectory))
    }

    /// Reads each event of the `transcript.jsonl` of a session directory.
    ///
    /// - Parameter directory: The recording directory of the session.
    /// - Returns: The events, in file order.
    /// - Throws: The error of the read, or of the decode of a line.
    static func events(in directory: URL) throws -> [TranscriptEvent] {
        let text = try String(contentsOf: directory.appendingPathComponent(transcriptFileName), encoding: .utf8)
        let decoder = JSONDecoder()
        return try text.split(separator: "\n").map { line in
            try decoder.decode(TranscriptEvent.self, from: Data(line.utf8))
        }
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
