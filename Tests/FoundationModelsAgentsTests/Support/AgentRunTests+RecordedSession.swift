import Testing

@testable import FoundationModelsAgents

/// The helpers that read the recording of the session of a run. Each suite
/// that reads a recorded session calls these helpers.
extension AgentRunTests {
    /// Reads the `index.md` record of the session of `run`.
    ///
    /// - Parameter run: A run that made a session.
    /// - Returns: The record of the session.
    /// - Throws: The error of `#require` when the run has no recording
    ///   directory, or the error of the read.
    static func recordedSession(of run: AgentRun) throws -> RecordedSession {
        let directory = try #require(run.recordingDirectory)
        return try RecordedSession.read(in: directory)
    }

    /// Gives the instructions that the session of `run` recorded.
    ///
    /// - Parameter run: A run that made a session.
    /// - Returns: The instructions.
    /// - Throws: The error of the read of the recording, or the error of
    ///   `#require` when the session recorded no instructions.
    static func instructions(of run: AgentRun) throws -> String {
        try #require(try recordedSession(of: run).configuration.instructions)
    }
}
