import FoundationModels
import FoundationModelsExtras
import ULID

/// A tool whose body reads the transcript of its own session through its `ToolContext`.
///
/// A test reads the outcome of each call from ``TranscriptProbeRecord``.
struct TranscriptProbeTool: Tool {
    /// The arguments of the tool: one text.
    @Generable
    struct Arguments {
        /// A text that the tool ignores.
        let text: String
    }

    /// What one call found.
    enum Outcome: Sendable, Equatable {
        /// The context gave the transcript.
        case read

        /// The context had no reader.
        case noSource

        /// The call had no context, or the read failed in another way.
        case other
    }

    /// The name of the tool.
    let name: String

    /// The description of the tool.
    let description = "A tool that reads the transcript of its own session."

    /// The record of the outcomes.
    let record: TranscriptProbeRecord

    /// Reads the transcript of the session of the call, and records the outcome.
    ///
    /// - Parameter arguments: The arguments, which the tool ignores.
    /// - Returns: A short text.
    func call(arguments: Arguments) async throws -> String {
        guard let context = ToolContext.current else {
            record.add(.other)
            return "The tool has no context."
        }
        do {
            _ = try await context.transcript(of: context.sessionID)
            record.add(.read)
        } catch SessionTranscriptError.noSource {
            record.add(.noSource)
        } catch {
            record.add(.other)
        }
        return "The probe is done."
    }
}

/// The outcomes of the ``TranscriptProbeTool`` instances of one test, in order.
typealias TranscriptProbeRecord = CallRecord<TranscriptProbeTool.Outcome>

/// A transcript reader that gives an empty transcript for any session.
struct EmptyTranscriptReader: SessionTranscriptReader {
    /// Gives an empty transcript.
    ///
    /// - Parameter sessionID: The session to read.
    /// - Returns: A transcript with no entries.
    func transcript(of sessionID: ULID) async throws -> SessionTranscript {
        SessionTranscript(sessionID: sessionID, entries: [])
    }
}
