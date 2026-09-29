import Testing

/// Guards the logging rule of the OpenTelemetry design of 2026-09-28: the
/// package writes its log records through `Logging.Logger` of swift-log, and
/// never through the unified logging of the operating system. A record of
/// `os.Logger` or a signpost of `OSSignposter` does not go to the logging
/// backend that the host bootstraps, thus the host cannot see it.
///
/// The suite gives `SwiftSourceScan` the test of a line below, and that reader
/// walks each Swift file under `Sources/`. A line breaks the rule when it
/// holds `import os`, `import OSLog`, `os.Logger` or `OSSignposter` as a full
/// token. Thus `import osmium` and `OSSignposterFixture` are not reported. A
/// comment line holds no code, thus the walk passes over it, as the other
/// guard suites do.
@Suite("No os logging")
struct NoOSLoggingTests {
    /// The tokens that no line of code may hold.
    private static let disallowedTokens = ["import os", "import OSLog", "os.Logger", "OSSignposter"]

    /// The source directory, relative to the package root.
    private static let sourcesPath = "Sources"

    @Test(arguments: [
        "import os",
        "import os.log",
        "import OSLog",
        "private let logger = os.Logger(subsystem: \"agents\", category: \"run\")",
        "let signposter = OSSignposter()"
    ])
    func aLineThatUsesOSLoggingIsReported(line: String) {
        #expect(Self.usesOSLogging(line))
    }

    @Test(arguments: [
        "import Logging",
        "import osmium",
        "let logger = Logger(label: AgentsTelemetry.logLabel)",
        "struct OSSignposterFixture {}",
        "/// Never write `import os` in this package.",
        "    // let logger = os.Logger()"
    ])
    func aLineThatUsesNoOSLoggingIsNotReported(line: String) {
        #expect(!Self.usesOSLogging(line))
    }

    @Test func theRuleFindsTheImportInAListOfLines() {
        let lines = [
            "import Logging",
            "// import os",
            "import os",
            "let logger = Logger(label: label)"
        ]

        #expect(SwiftSourceScan.lineNumbers(in: lines, matching: Self.usesOSLogging) == [3])
    }

    @Test func noFileUnderSourcesUsesOSLogging() throws {
        let offenders = try SwiftSourceScan.reportedLines(inDirectory: Self.sourcesPath, matching: Self.usesOSLogging)

        #expect(
            offenders.isEmpty,
            """
            No file under Sources/ may use os.Logger, import os, import OSLog or OSSignposter. Write each \
            log record with Logging.Logger of swift-log; found: \(offenders.joined(separator: ", "))
            """)
    }

    /// Tells whether `line` uses the unified logging of the operating system.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line is not a comment and holds one of the
    ///   disallowed tokens as a full token.
    private static func usesOSLogging(_ line: String) -> Bool {
        !SwiftSourceScan.isComment(line)
            && disallowedTokens.contains { SwiftSourceScan.holds(token: $0, in: line) }
    }
}
