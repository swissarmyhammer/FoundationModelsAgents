import Foundation
import Testing
import ULID

@testable import FoundationModelsAgents

/// The record of the task prompt of a run beside the `index.md` of its session.
@Suite("The task prompt record of a run")
struct AgentTaskPromptRecordTests {
    /// A task prompt with text that is not ASCII.
    private static let prompt = "Review the diff — every file, and the tests."

    /// A recording root in a new temporary folder, and one session folder in it.
    private struct Root {
        let url: URL
        let session: ULID

        /// The folder of the session: `<root>/<session>/`.
        var sessionFolder: URL {
            url.appendingPathComponent(session.description, isDirectory: true)
        }

        /// Makes the root and, when `withSessionFolder` is `true`, the folder of the session.
        static func make(withSessionFolder: Bool = true) throws -> Root {
            let url = FileManager.default.temporaryDirectory
                .appending(path: "AgentTaskPromptRecordTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            let root = Root(url: url, session: ULID())
            let folder = withSessionFolder ? root.sessionFolder : url
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return root
        }

        /// Deletes the root.
        func delete() throws {
            try FileManager.default.removeItem(at: url)
        }
    }

    @Test("a written record reads back as the same prompt")
    func writtenRecordReadsBack() throws {
        let root = try Root.make()
        defer { try? root.delete() }

        try AgentTaskPromptRecord.write(Self.prompt, inSessionFolder: root.sessionFolder)

        #expect(try AgentTaskPromptRecord.read(of: root.session, under: root.url) == Self.prompt)
    }

    @Test("a session with no recording folder gets no record and no folder")
    func noFolderGetsNoRecord() throws {
        let root = try Root.make(withSessionFolder: false)
        defer { try? root.delete() }

        try AgentTaskPromptRecord.write(Self.prompt, inSessionFolder: root.sessionFolder)

        #expect(!FileManager.default.fileExists(atPath: root.sessionFolder.path(percentEncoded: false)))
    }

    @Test("a session folder with no record reads as no prompt")
    func folderWithoutRecordReadsAsNil() throws {
        let root = try Root.make()
        defer { try? root.delete() }

        #expect(try AgentTaskPromptRecord.read(of: root.session, under: root.url) == nil)
    }

    @Test("a record that is not UTF-8 text is an error")
    func recordThatIsNotTextThrows() throws {
        let root = try Root.make()
        defer { try? root.delete() }
        let file = root.sessionFolder.appendingPathComponent(AgentTaskPromptRecord.fileName, isDirectory: false)
        try Data([0xFF, 0xFE, 0xC3, 0x28]).write(to: file)

        #expect(throws: AgentTaskPromptRecord.ReadError.notText) {
            try AgentTaskPromptRecord.read(of: root.session, under: root.url)
        }
    }
}
