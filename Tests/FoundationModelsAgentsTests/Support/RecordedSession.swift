import Foundation
import FoundationModelsRouter

/// The parts of the `session.json` of a Router session that the `AgentRun`
/// tests read.
///
/// The fields of `SessionSidecar` are internal to the Router, thus the test
/// decodes the file into this subset.
struct RecordedSidecar: Decodable {
    /// The parts of the configuration of the session.
    struct Configuration: Decodable {
        /// The instructions of the session.
        let instructions: String?

        /// The token budget of the session.
        let budget: TokenBudget?

        /// The prompt of the automatic folds.
        let compactionPrompt: CompactionPrompt
    }

    /// The name of the file in the session directory.
    static let fileName = "session.json"

    /// The slot of the session.
    let slot: ModelSlot

    /// The lineage record of the session, or `nil`.
    let agentSpawn: SessionSidecar.AgentSpawn?

    /// The configuration of the session.
    let configuration: Configuration

    /// Reads the `session.json` of the session directory `directory`.
    ///
    /// - Parameter directory: The recording directory of the session.
    /// - Returns: The decoded parts.
    /// - Throws: The error of the read or of the decode.
    static func read(in directory: URL) throws -> RecordedSidecar {
        try JSONDecoder().decode(
            RecordedSidecar.self, from: Data(contentsOf: directory.appendingPathComponent(fileName)))
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
        let text = try String(contentsOf: directory.appendingPathComponent(fileName), encoding: .utf8)
        let decoder = JSONDecoder()
        return try text.split(separator: "\n").flatMap { line in
            try decoder.decode(TranscriptEvent.self, from: Data(line.utf8)).operationEvents
        }
    }
}
