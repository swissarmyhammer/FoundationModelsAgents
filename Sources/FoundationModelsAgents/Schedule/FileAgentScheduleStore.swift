import Foundation
import ULID

/// Saves the scheduled agents of each session as one JSON file in the folder
/// of the session, for example its recording folder. Thus the tasks live and
/// go with the session.
public struct FileAgentScheduleStore: AgentScheduleStore {
    /// The name of the file in the folder of a session.
    public static let fileName = "schedules.json"

    /// Gives the folder of a session, or `nil` when the session has none.
    public typealias SessionFolder = @Sendable (ULID) async -> URL?

    /// The folder of each session.
    private let folder: SessionFolder

    /// Makes a store.
    ///
    /// - Parameter folder: Gives the folder of a session, for example
    ///   `{ directory.session(id: $0)?.recordingDirectory }`.
    public init(folder: @escaping SessionFolder) {
        self.folder = folder
    }

    /// Writes the tasks of `owner`, in place of the file. An empty list
    /// removes the file.
    ///
    /// - Parameters:
    ///   - tasks: The tasks.
    ///   - owner: The session.
    /// - Throws: The error of the encoder or of the file system.
    public func save(_ tasks: [AgentScheduledTask], of owner: ULID) async throws {
        guard let file = await file(of: owner) else { return }
        guard !tasks.isEmpty else {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            return
        }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(tasks).write(to: file, options: .atomic)
    }

    /// Reads the tasks of `owner`.
    ///
    /// - Parameter owner: The session.
    /// - Returns: The tasks, or none when the session has no file.
    /// - Throws: The error of the decoder or of the file system.
    public func load(of owner: ULID) async throws -> [AgentScheduledTask] {
        guard let file = await file(of: owner), FileManager.default.fileExists(atPath: file.path) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AgentScheduledTask].self, from: Data(contentsOf: file))
    }

    /// The file of a session.
    ///
    /// - Parameter owner: The session.
    /// - Returns: The file, or `nil` when the session has no folder.
    private func file(of owner: ULID) async -> URL? {
        await folder(owner)?.appendingPathComponent(Self.fileName, isDirectory: false)
    }
}
