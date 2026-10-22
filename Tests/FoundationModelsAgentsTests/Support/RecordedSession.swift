import Foundation
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

/// The record of a Router session that the `AgentRun` tests read: the
/// ``SessionRecord`` in the frontmatter of the `index.md` of the session
/// directory.
///
/// The Router reads the record with
/// `RouterSessionDirectory.recordedSessions(in:)`. The configuration of the
/// record is internal to the Router, thus the test decodes the parts of it
/// that it reads from the frontmatter.
struct RecordedSession {
    /// The parts of the configuration of the session.
    struct Configuration: Decodable {
        /// The instructions of the session.
        let instructions: String?

        /// The token budget of the session.
        let budget: TokenBudget?

        /// The prompt of the automatic folds.
        let compactionPrompt: CompactionPrompt
    }

    /// The frontmatter key of the configuration.
    private struct Frontmatter: Decodable {
        /// The configuration of the session.
        let configuration: Configuration
    }

    /// The name of the file in the session directory.
    static let fileName = "index.md"

    /// The record of the session.
    let record: SessionRecord

    /// The configuration of the session.
    let configuration: Configuration

    /// The slot of the session.
    var slot: ModelSlot { record.slot }

    /// The lineage record of the session, or `nil`.
    var agentSpawn: SessionRecord.AgentSpawn? { record.agentSpawn }

    /// The working directory of the session.
    var workingDirectory: URL { record.workingDirectory }

    /// Reads the record of the session directory `directory`.
    ///
    /// - Parameter directory: The recording directory of the session.
    /// - Returns: The record and its configuration.
    /// - Throws: The error of `#require` when the recording root lists no
    ///   session of the directory or the `index.md` has no frontmatter, or
    ///   the error of the read or of the decode.
    static func read(in directory: URL) throws -> RecordedSession {
        let sessionId = directory.lastPathComponent
        let record = try #require(
            try RouterSessionDirectory.recordedSessions(in: directory.deletingLastPathComponent())
                .first { $0.sessionId.description == sessionId })
        let text = try String(contentsOf: directory.appendingPathComponent(fileName), encoding: .utf8)
        let frontmatter = try #require(FrontmatterDocument<Never>.split(text: text).frontmatter)
        let configuration = try YAMLValue.parse(frontmatter).decoded(as: Frontmatter.self).configuration
        return RecordedSession(record: record, configuration: configuration)
    }
}

/// Reads the `transcript.jsonl` of a Router session.
enum RecordedTranscript {
    /// The name of the file in the session directory.
    static let fileName = "transcript.jsonl"

    /// The operation events that the transcript of the session journaled.
    ///
    /// - Parameter directory: The recording directory of the session.
    /// - Returns: The events, in file order.
    /// - Throws: The error of the read or of the decode of a line.
    static func operationEvents(in directory: URL) throws -> [OperationEvent] {
        try events(in: directory).flatMap(\.operationEvents)
    }

    /// The operation events that the run journal of the session recorded:
    /// one `.toolOutput` entry for each event at the moment it was posted.
    ///
    /// The Router writes a delivered event a second time on the `.prompt`
    /// entry of the submission that delivered it. This read leaves out that
    /// copy, thus each post counts one time.
    ///
    /// - Parameter directory: The recording directory of the session.
    /// - Returns: The events, in file order.
    /// - Throws: The error of the read or of the decode of a line.
    static func journaledEvents(in directory: URL) throws -> [OperationEvent] {
        try events(in: directory).filter { $0.kind == .toolOutput }.flatMap(\.operationEvents)
    }

    /// The events of the transcript of the session, read as the Router reads
    /// them: with `JSONLFile`, which decodes the millisecond ISO 8601 dates.
    ///
    /// - Parameter directory: The recording directory of the session.
    /// - Returns: The events, in file order.
    /// - Throws: The error of the read.
    private static func events(in directory: URL) throws -> [TranscriptEvent] {
        try JSONLFile(url: directory.appendingPathComponent(fileName)).records(as: TranscriptEvent.self)
    }
}
