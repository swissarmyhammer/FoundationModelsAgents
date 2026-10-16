import Testing

/// Guards the rule of decision D61: the agent-folder source is an optional
/// input that the host gives, and the package holds no code of a cloud sync
/// service. The package names no container id, no path of a sync service,
/// and no ubiquity API. The host gives the URL of its synced folder.
///
/// The suite gives `SwiftSourceScan` the test of a line below, and that reader
/// walks each Swift file under `Sources/`. A line breaks the rule when it
/// holds one of the disallowed texts in any letter case. The rule also reads
/// the comment lines, because a comment that names the service ties the
/// package to it as much as code does.
@Suite("No cloud sync code")
struct NoCloudSyncCodeTests {
    /// The texts that no line may hold, in lowercase. A container id starts
    /// with the name of the service, thus the first text also finds it.
    private static let disallowedTexts = ["icloud", "ubiquit"]

    /// The source directory, relative to the package root.
    private static let sourcesPath = "Sources"

    @Test(arguments: [
        "let container = \"iCloud.com.example.agents\"",
        "let url = FileManager.default.url(forUbiquityContainerIdentifier: nil)",
        "/// The iCloud Agents/ folder of the app.",
        "let key = NSMetadataUbiquitousItemDownloadingStatusKey",
        "guard name.hasSuffix(\".icloud\") else { return nil }"
    ])
    func aLineThatNamesTheSyncServiceIsReported(line: String) {
        #expect(Self.namesTheSyncService(line))
    }

    @Test(arguments: [
        "let folders: [URL] = agentFolders",
        "/// A hidden name that holds the name of the document is a placeholder.",
        "NSFileCoordinator(filePresenter: nil)"
    ])
    func aLineThatNamesNoSyncServiceIsNotReported(line: String) {
        #expect(!Self.namesTheSyncService(line))
    }

    @Test func noFileUnderSourcesNamesTheSyncService() throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.sourcesPath, matching: Self.namesTheSyncService)

        #expect(
            offenders.isEmpty,
            """
            No file under Sources/ may name a cloud sync service, a container id, or a ubiquity API. \
            The host gives the URL of its synced folder in agentFolders; found: \
            \(offenders.joined(separator: ", "))
            """)
    }

    /// Tells whether `line` names the cloud sync service.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line holds one of the disallowed texts in
    ///   any letter case.
    private static func namesTheSyncService(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return disallowedTexts.contains { lowercased.contains($0) }
    }
}
