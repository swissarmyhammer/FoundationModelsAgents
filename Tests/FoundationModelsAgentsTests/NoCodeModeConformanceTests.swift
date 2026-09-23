import Testing

/// Guards plan.md §9.5: the `agents` tool is not a code-mode surface. No type
/// of the library conforms to `OperationDescribing` or to `ForkableTool`.
///
/// A run is a session with its own turns, not a script verb. The lineage of a
/// run and its final message need a Router session as the caller. Thus a host
/// registers the `agents` tool directly on its session.
///
/// The suite gives `SwiftSourceScan` the test of a line below, and that reader
/// walks each Swift file under `Sources/FoundationModelsAgents/`. A line of
/// code breaks the rule when it holds one of the two names as a full token.
/// Thus `OperationDescribingFixture` is not reported. A comment line holds no
/// code, thus a doc comment can tell that the tool does not conform.
@Suite("No code-mode conformance")
struct NoCodeModeConformanceTests {
    /// The directory of the library source, relative to the package root.
    private static let sourcesPath = "Sources/FoundationModelsAgents"

    /// The code-mode protocols that no line of code may name.
    private static let codeModeProtocols = ["OperationDescribing", "ForkableTool"]

    @Test(arguments: [
        "extension AgentsTool: OperationDescribing {",
        "struct AgentsTool: OperationTool, ForkableTool {",
        "    let described: any OperationDescribing",
        "extension AgentsTool: FoundationModelsExtras.ForkableTool {"
    ])
    func aLineThatNamesACodeModeProtocolIsReported(line: String) {
        #expect(Self.namesACodeModeProtocol(line))
    }

    @Test(arguments: [
        "/// `AgentsTool` does not conform to `OperationDescribing` or `ForkableTool`.",
        "struct OperationDescribingFixture {",
        "let tool = MyForkableTool()",
        "extension AgentsTool: OperationTool {"
    ])
    func aLineThatNamesNoCodeModeProtocolIsNotReported(line: String) {
        #expect(!Self.namesACodeModeProtocol(line))
    }

    @Test func theRuleFindsTheConformanceInAListOfLines() {
        let lines = [
            "import FoundationModelsExtras",
            "/// Not a code-mode surface: no `ForkableTool` here.",
            "struct AgentsTool: OperationTool {}",
            "extension AgentsTool: ForkableTool {}"
        ]

        #expect(SwiftSourceScan.lineNumbers(in: lines, matching: Self.namesACodeModeProtocol) == [4])
    }

    @Test func noFileOfTheLibraryNamesACodeModeProtocol() throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.sourcesPath, matching: Self.namesACodeModeProtocol)

        #expect(
            offenders.isEmpty,
            """
            No file under \(Self.sourcesPath)/ may name OperationDescribing or ForkableTool: the \
            agents tool is not a code-mode surface (plan.md §9.5); found: \(offenders.joined(separator: ", "))
            """)
    }

    /// Tells whether `line` is code that names a code-mode protocol.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line is not a comment, and it holds one of
    ///   the two names as a full token.
    private static func namesACodeModeProtocol(_ line: String) -> Bool {
        !SwiftSourceScan.isComment(line)
            && codeModeProtocols.contains { SwiftSourceScan.holds(token: $0, in: line) }
    }
}
