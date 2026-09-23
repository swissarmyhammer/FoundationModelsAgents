import Testing

/// Guards the `no_direct_standard_out_logs` rule of the code hygiene gate: no
/// line of this package, and no line of its example, writes to a standard
/// stream with `print`, `debugPrint`, `dump` or `_printChanges`. Each line
/// goes through `StandardStream`, the one line writer.
///
/// The suite gives `SwiftSourceScan` the test of a line below, and that reader
/// walks each Swift file under `Sources/` and `Examples/agents-demo/`. A call
/// is the name of one of the four and the `(` that opens its arguments, with
/// no letter, digit or underscore before the name. Thus `sprint(x)` and
/// `printableLine(x)` are not reported. A comment line holds no code, thus the
/// walk passes over it, as the `match_kinds: [identifier]` key of the rule
/// itself does.
@Suite("No standard out write")
struct NoStandardOutWriteTests {
    /// The calls that no line of code may hold. Each one is a name and the
    /// `(` that opens its arguments.
    private static let disallowedCalls = ["print(", "debugPrint(", "dump(", "_printChanges("]

    @Test(arguments: [
        "print(\"hello\")",
        "debugPrint(value)",
        "dump(value)",
        "Self._printChanges()",
        "        print(\"indented\")"
    ])
    func aLineThatCallsOneOfTheFourIsReported(line: String) {
        #expect(Self.writesToAStandardStream(line))
    }

    @Test(arguments: [
        "Self.printableLine(of: text)",
        "sprintDistance()",
        "StandardStream.output.write(line: text)",
        "// print(\"a comment holds no code\")",
        "/// The one writer, which `dump(_:)` never replaces."
    ])
    func aLineThatCallsNoneOfTheFourIsNotReported(line: String) {
        #expect(!Self.writesToAStandardStream(line))
    }

    @Test func theRuleFindsTheWriteInAListOfLines() {
        let lines = [
            "import FoundationModelsSkills",
            "// print(\"a comment holds no code\")",
            "print(AgentsDemoUsage.text)",
            "StandardStream.output.write(line: AgentsDemoUsage.text)"
        ]

        #expect(SwiftSourceScan.lineNumbers(in: lines, matching: Self.writesToAStandardStream) == [3])
    }

    @Test(arguments: ["Sources", "Examples/agents-demo"])
    func noFileOfTheDirectoryWritesToAStandardStreamWithACall(directory: String) throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: directory, matching: Self.writesToAStandardStream)

        #expect(
            offenders.isEmpty,
            """
            No file may write to a standard stream with print, debugPrint, dump or _printChanges. Write \
            each line with StandardStream; found: \(offenders.joined(separator: ", "))
            """)
    }

    /// Tells whether `line` writes to a standard stream with a call to one of
    /// the four.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line holds code that calls one of the four.
    private static func writesToAStandardStream(_ line: String) -> Bool {
        !SwiftSourceScan.isComment(line)
            && disallowedCalls.contains { SwiftSourceScan.holds(token: $0, in: line) }
    }
}
