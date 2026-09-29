@testable import FoundationModelsAgents
import InMemoryLogging
import Logging
import ULID

/// The log records of one telemetry capture, read by message and by run.
///
/// A run writes three records: the "enter" record of `TracedCall`, the start
/// record, and one end record. This reader finds each of them from its
/// message and from the run id in its metadata.
struct CapturedLog {
    /// The log records of the capture, in the order of the calls.
    let records: [InMemoryLogHandler.Entry]

    /// Gives the "enter" records of the span of a run. The message of such a
    /// record ends with the span name.
    var enterRecords: [InMemoryLogHandler.Entry] {
        records.filter { "\($0.message)".hasSuffix(AgentsTelemetry.SpanName.run) }
    }

    /// Gives the start records of each run.
    var startRecords: [InMemoryLogHandler.Entry] {
        records(withMessage: AgentsTelemetry.LogMessage.runStarted)
    }

    /// Gives the end records of each run: finished, failed and cancelled.
    var endRecords: [InMemoryLogHandler.Entry] {
        let messages = [AgentsTelemetry.Outcome.finished, .failed, .cancelled].map(AgentsTelemetry.LogMessage.runEnded)
        return records.filter { messages.contains("\($0.message)") }
    }

    /// Gives the records whose message is `message`.
    ///
    /// - Parameter message: The message of the records.
    /// - Returns: The records, in the order of the calls.
    func records(withMessage message: String) -> [InMemoryLogHandler.Entry] {
        records.filter { "\($0.message)" == message }
    }

    /// Gives the records of one run: each record whose run id is the id of
    /// the run.
    ///
    /// - Parameters:
    ///   - selected: The records to read.
    ///   - runID: The id of the run.
    /// - Returns: The records of the run, in the order of the calls.
    static func records(
        _ selected: [InMemoryLogHandler.Entry], ofRun runID: ULID
    ) -> [InMemoryLogHandler.Entry] {
        selected.filter { $0.metadata[AgentsTelemetry.LogMetadataKey.runID] == .string(runID.description) }
    }
}
