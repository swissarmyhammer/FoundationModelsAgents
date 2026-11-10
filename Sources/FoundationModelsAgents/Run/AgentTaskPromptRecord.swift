import Foundation
import ULID

/// The task prompt of a run, on disk beside the `index.md` of its session.
///
/// The Router records the first prompt of a session only when the pump of the session takes
/// the mail of that prompt (`RouterSessionDirectory.firstPrompt(of:)`). The host sees a run
/// before that time: the runner puts the run in its index, and the caller lists the run as
/// background work. A kill in that interval leaves a recorded child with no first prompt. Thus
/// a new run writes its task prompt to this record when it makes its session, before the runner
/// puts it in the index. The restore reads this record first
/// (``AgentRunner/restoreInterrupted(of:caller:directory:prompts:)``).
///
/// The file holds the text of the prompt as UTF-8, and nothing else. The Router finds a session
/// folder by its `index.md`, thus this file does not change what the Router reads.
enum AgentTaskPromptRecord {
    /// The name of the file in the recording folder of the session.
    static let fileName = "task-prompt.md"

    /// Writes `prompt` to the recording folder `folder` of a new session.
    ///
    /// A session with no recording has no folder. That session has no record to restore, thus
    /// the call then writes nothing.
    ///
    /// - Parameters:
    ///   - prompt: The task prompt of the run.
    ///   - folder: The recording folder of the session (`RoutedSession.recordingDirectory`).
    /// - Throws: The error of the write.
    static func write(_ prompt: String, inSessionFolder folder: URL) throws {
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        try Data(prompt.utf8).write(to: file(inSessionFolder: folder), options: .atomic)
    }

    /// Reads the task prompt of the session `session` under the recording root `recordingRoot`.
    ///
    /// The folder of a session under a recording root that the host gives is
    /// `<recordingRoot>/<session>/`, the layout of the Router.
    ///
    /// - Parameters:
    ///   - session: The id of the session.
    ///   - recordingRoot: The recording root of the runs (``AgentEnvironment/recordingRoot``).
    /// - Returns: The task prompt, or `nil` when the folder has no record.
    /// - Throws: The error of a read of a record that exists, or ``ReadError/notText`` for a
    ///   record that is not UTF-8 text.
    static func read(of session: ULID, under recordingRoot: URL) throws -> String? {
        let folder = recordingRoot.appendingPathComponent(session.description, isDirectory: true)
        let file = file(inSessionFolder: folder)
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return nil }
        guard let prompt = String(data: try Data(contentsOf: file), encoding: .utf8) else {
            throw ReadError.notText
        }
        return prompt
    }

    /// An error of ``read(of:under:)``.
    enum ReadError: Error, Equatable {
        /// The record is not UTF-8 text.
        case notText
    }

    /// The file of the record in the recording folder `folder` of a session.
    ///
    /// - Parameter folder: The recording folder of the session.
    /// - Returns: The URL of the file.
    private static func file(inSessionFolder folder: URL) -> URL {
        folder.appendingPathComponent(fileName, isDirectory: false)
    }
}
