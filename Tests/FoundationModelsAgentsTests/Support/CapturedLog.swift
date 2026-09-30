@testable import FoundationModelsAgents
import TelemetryTestSupport
import Logging
import ULID

/// The log records of one telemetry capture, read by message and by run.
///
/// A run writes three records: the "enter" record of `TracedCall`, the start
/// record, and one end record. This reader finds each of them from its
/// message and from the run id in its metadata.
struct CapturedLog {
    /// The log records of the capture, in the order of the calls.
    let records: [TelemetryCapture.LogRecord]

    /// Gives the "enter" records of the span of a run. The message of such a
    /// record ends with the span name.
    var enterRecords: [TelemetryCapture.LogRecord] {
        records.filter { "\($0.message)".hasSuffix(AgentsTelemetry.SpanName.run) }
    }

    /// Gives the start records of each run.
    var startRecords: [TelemetryCapture.LogRecord] {
        records(withMessage: AgentsTelemetry.LogMessage.runStarted)
    }

    /// Gives the end records of each run: finished, failed and cancelled.
    var endRecords: [TelemetryCapture.LogRecord] {
        let messages = [AgentsTelemetry.Outcome.finished, .failed, .cancelled].map(AgentsTelemetry.LogMessage.runEnded)
        return records.filter { messages.contains("\($0.message)") }
    }

    /// Gives the records whose message is `message`.
    ///
    /// - Parameter message: The message of the records.
    /// - Returns: The records, in the order of the calls.
    func records(withMessage message: String) -> [TelemetryCapture.LogRecord] {
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
        _ selected: [TelemetryCapture.LogRecord], ofRun runID: ULID
    ) -> [TelemetryCapture.LogRecord] {
        selected.filter { $0.metadata[AgentsTelemetry.LogMetadataKey.runID] == .string(runID.description) }
    }
}
