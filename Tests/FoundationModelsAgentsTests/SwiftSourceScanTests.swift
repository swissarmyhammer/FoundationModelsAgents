import Testing

/// Holds `SwiftSourceScan`, the source reader that the guard suites share, to
/// its contract: it counts the lines of a text from 1, it walks the Swift
/// files of a directory, and it stops a walk that finds no Swift file.
///
/// Each guard suite gives the reader one test of a line. This suite holds the
/// steps under that test, thus no guard keeps a case for them.
@Suite("Swift source scan")
struct SwiftSourceScanTests {
    /// The directory of the demonstration example, relative to the package
    /// root. Each source file of it is a Swift file that imports a module.
    private static let exampleDirectory = "Examples/agents-demo"

    /// A directory of the package that holds files and no Swift file.
    private static let directoryWithNoSwiftFile = ".github"

    /// The text that opens the import line of a Swift file.
    private static let importMarker = "import "

    /// The text that stands between a path and a line number.
    private static let lineNumberMarker = ".swift:"

    @Test func theReportedLineNumberCountsFromOne() {
        let text = """
            let first = "alpha"
            let second = "bravo"
            let third = "charlie"
            """

        #expect(SwiftSourceScan.lineNumbers(in: text) { $0.contains("charlie") } == [3])
    }

    @Test func aListOfLinesGivesTheNumberOfEachReportedLine() {
        let lines = ["let first = 1", "let second = 2", "let third = 1"]

        #expect(SwiftSourceScan.lineNumbers(in: lines) { $0.hasSuffix("= 1") } == [1, 3])
    }

    @Test func aTextWithNoReportedLineGivesNoNumber() {
        #expect(SwiftSourceScan.lineNumbers(in: "one line") { _ in false }.isEmpty)
    }

    @Test func theWalkNamesTheDirectoryThePathAndTheLineNumber() throws {
        let reported = try SwiftSourceScan.reportedLines(inDirectory: Self.exampleDirectory) {
            $0.hasPrefix(Self.importMarker)
        }

        #expect(!reported.isEmpty, "each file of the example imports, or this case proves nothing")
        #expect(
            reported.allSatisfy {
                $0.hasPrefix("\(Self.exampleDirectory)/") && $0.contains(Self.lineNumberMarker)
            })
    }

    @Test func aWalkThatFindsNoSwiftFileStops() {
        #expect(throws: SwiftSourceScan.ScanError.self) {
            try SwiftSourceScan.reportedLines(inDirectory: Self.directoryWithNoSwiftFile) { _ in true }
        }
    }
}
