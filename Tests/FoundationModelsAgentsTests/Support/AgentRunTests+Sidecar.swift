import Testing

@testable import FoundationModelsAgents

/// The helpers that read the recording of the session of a run. Each suite
/// that reads a recorded session calls these helpers.
extension AgentRunTests {
    /// Reads the `session.json` of the session of `run`.
    ///
    /// - Parameter run: A run that made a session.
    /// - Returns: The decoded parts of the file.
    /// - Throws: The error of `#require` when the run has no recording
    ///   directory, or the error of the read.
    static func sidecar(of run: AgentRun) throws -> RecordedSidecar {
        let directory = try #require(run.recordingDirectory)
        return try RecordedSidecar.read(in: directory)
    }

    /// Gives the instructions that the session of `run` recorded.
    ///
    /// - Parameter run: A run that made a session.
    /// - Returns: The instructions.
    /// - Throws: The error of the read of the recording, or the error of
    ///   `#require` when the session recorded no instructions.
    static func instructions(of run: AgentRun) throws -> String {
        try #require(try sidecar(of: run).configuration.instructions)
    }
}
