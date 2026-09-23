import Testing

/// Guards the loading boundary of this package (plan.md §15): the raw work of
/// loading an agent lives in `FoundationModelsExtras`, and this package keeps
/// only the work of the agent schema.
///
/// The rule, in one table:
///
/// | the work | where it lives |
/// |---|---|
/// | fetch a marketplace and materialize a layer root | Extras, `Marketplace` |
/// | find a file in the combined view of the layers | Extras, `DotfolderStack` |
/// | say that a layer root changed | Extras, `DotfolderWatcher` |
/// | split the frontmatter from the body | Extras, `FrontmatterDocumentStack` |
/// | render with Stencil, with the trust of the layer | Extras, `StenciledDotfolderStack` |
/// | everything above: the agent schema | here |
///
/// This suite gives `SwiftSourceScan` a test of a line, and that reader walks
/// every Swift file under `Sources/FoundationModelsAgents/`. The walk reads
/// the full text of each file, comments included, thus a stale doc comment
/// fails it as well as a line of code.
///
/// ``rules`` is the table, and each row states one rule: the text that no
/// line may hold, why the boundary forbids it, and the files that may hold it
/// all the same. An exemption that exempts no line is dead, and the suite
/// fails on it.
@Suite("Loading boundary")
struct LoadingBoundaryTests {
    /// The directory of this package's own source, relative to the package
    /// root.
    private static let sourcesPath = "Sources/FoundationModelsAgents"

    /// A file that the sample rule exempts. The exemption tests below read
    /// it; no such file is in the package.
    private static let sampleExemptFile = "\(sourcesPath)/Sample/ExemptFile.swift"

    /// A file that the sample rule does not exempt.
    private static let sampleOtherFile = "\(sourcesPath)/Sample/OtherFile.swift"

    /// The rule that the exemption tests below read. It is not in ``rules``.
    /// It has one exemption, thus it shows each path of the exemption check.
    private static let sampleRule = Rule(
        name: "SampleForbiddenName",
        reason: "the exemption tests of this suite read this rule",
        exemptFiles: [sampleExemptFile])

    /// The rule of the byte reader of Foundation, which the scan tests below
    /// read as one real row of ``rules``.
    private static let fileHandleRule = Rule(
        name: "FileHandle",
        reason: "the stack of Extras reads the bytes of a file",
        exemptFiles: [])

    /// One rule of the loading boundary.
    struct Rule: Sendable, CustomStringConvertible {
        /// The character that stands between the path of a reported line and
        /// the number of that line.
        private static let lineNumberSeparator = ":"

        /// The text that no line of a guarded file may hold.
        let name: String

        /// Why the loading boundary forbids the name.
        let reason: String

        /// The files that may hold the name all the same, by path relative to
        /// the package root.
        let exemptFiles: [String]

        /// The name of the rule, which names the test case in a report.
        var description: String { name }

        /// Tells whether `line` breaks this rule.
        ///
        /// - Parameter line: The line to read.
        /// - Returns: `true` when the line holds ``name``.
        func isBroken(by line: String) -> Bool {
            line.contains(name)
        }

        /// Tells whether an exempt file holds `reportedLine`.
        ///
        /// - Parameter reportedLine: One reported line, in the form
        ///   `<path>:<line number>`.
        /// - Returns: `true` when ``exemptFiles`` holds the path of the line.
        func exempts(_ reportedLine: String) -> Bool {
            exemptFiles.contains { Self.isLine(reportedLine, of: $0) }
        }

        /// Finds each exempt file that holds none of `reportedLines`.
        ///
        /// - Parameter reportedLines: Each reported line of the rule, the
        ///   exempt files included, in the form `<path>:<line number>`.
        /// - Returns: Each exempt file that exempts no line. Such an exemption
        ///   is dead.
        func unusedExemptions(in reportedLines: [String]) -> [String] {
            exemptFiles.filter { exemptFile in
                !reportedLines.contains { Self.isLine($0, of: exemptFile) }
            }
        }

        /// Tells whether `reportedLine` is a line of `file`.
        ///
        /// - Parameters:
        ///   - reportedLine: One reported line, in the form
        ///     `<path>:<line number>`.
        ///   - file: A file path relative to the package root.
        /// - Returns: `true` when the path of the line is `file`, and not
        ///   only a path that starts with the text of `file`.
        private static func isLine(_ reportedLine: String, of file: String) -> Bool {
            reportedLine.hasPrefix(file + lineNumberSeparator)
        }
    }

    /// Every rule of the loading boundary, with the reason of each one.
    static let rules: [Rule] = [
        Rule(
            name: "FileManager",
            reason: "the stack of Extras opens each directory and each file of an agent",
            exemptFiles: []),
        fileHandleRule,
        Rule(
            name: "String(contentsOf",
            reason: "FrontmatterDocumentStack of Extras reads the text of each agents/<id>.md",
            exemptFiles: []),
        Rule(
            name: "Data(contentsOf",
            reason: "the stack of Extras loads each file, thus this package loads no whole file",
            exemptFiles: []),
        Rule(
            name: "resourceValues",
            reason: "the stack of Extras reads the attributes of a file",
            exemptFiles: []),
        Rule(
            name: "contentsOfDirectory",
            reason: "the stack of Extras gives the union of the paths of the layers",
            exemptFiles: []),
        Rule(
            name: "DispatchSource",
            reason: "DotfolderWatcher of Extras holds the watch of each layer root",
            exemptFiles: []),
        Rule(
            name: "O_EVTONLY",
            reason: "DotfolderWatcher of Extras opens the descriptor of a watch",
            exemptFiles: []),
        Rule(
            name: "resolvingSymlinksInPath",
            reason: "the stack of Extras confines each path and resolves each link",
            exemptFiles: []),
        Rule(
            name: "FrontmatterDocument.split",
            reason: "FrontmatterDocumentStack of Extras splits the frontmatter from the body",
            exemptFiles: []),
        Rule(
            name: "TemplateEngine",
            reason: "StenciledDotfolderStack of Extras runs each render",
            exemptFiles: []),
        Rule(
            name: "TemplateContext",
            reason: "the stenciled stack of Extras builds the context of a render",
            exemptFiles: []),
        Rule(
            name: "TemplateValue",
            reason: "the stenciled stack of Extras carries each quarantined span as a value",
            exemptFiles: []),
        Rule(
            name: "WellKnownValues",
            reason: "the stenciled stack of Extras holds the lowest step of the variable ladder",
            exemptFiles: []),
        Rule(
            name: "import Stencil",
            reason: "Extras holds the one dependency on Stencil",
            exemptFiles: []),
        Rule(
            name: "import libgit2",
            reason: "the Marketplace module of Extras holds the one dependency on libgit2",
            exemptFiles: [])
    ]

    @Test(arguments: LoadingBoundaryTests.rules)
    func noFileOfThisPackageBreaksTheRule(rule: Rule) throws {
        let offenders = try Self.reportedLines(of: rule).filter { !rule.exempts($0) }

        #expect(
            offenders.isEmpty,
            """
            No file under \(Self.sourcesPath)/ may name \(rule.name): \(rule.reason). \
            Found: \(offenders.joined(separator: ", "))
            """)
    }

    @Test(arguments: LoadingBoundaryTests.rules)
    func eachExemptFileOfTheRuleNamesIt(rule: Rule) throws {
        let unused = rule.unusedExemptions(in: try Self.reportedLines(of: rule))

        #expect(
            unused.isEmpty,
            """
            \(unused.joined(separator: ", ")) is exempt from \(rule.name), and it names \
            \(rule.name) nowhere. An exemption that exempts nothing is dead; take it out of the table.
            """)
    }

    @Test func anExemptionThatExemptsNoLineIsUnused() {
        let reported = ["\(Self.sampleOtherFile):7"]

        #expect(Self.sampleRule.unusedExemptions(in: reported) == [Self.sampleExemptFile])
    }

    @Test func anExemptionThatExemptsALineIsUsed() {
        let reported = ["\(Self.sampleOtherFile):7", "\(Self.sampleExemptFile):32"]

        #expect(Self.sampleRule.unusedExemptions(in: reported).isEmpty)
    }

    @Test func aLineOfAFileWhoseNameOnlyOpensAnExemptNameDoesNotUseTheExemption() {
        let reported = ["\(Self.sampleExemptFile)Extra.swift:32"]

        #expect(Self.sampleRule.unusedExemptions(in: reported) == [Self.sampleExemptFile])
    }

    @Test func aLineOfAnExemptFileIsNotReported() {
        #expect(Self.sampleRule.exempts("\(Self.sampleExemptFile):32"))
    }

    @Test func aLineOfAnotherFileIsReported() {
        #expect(!Self.sampleRule.exempts("\(Self.sampleOtherFile):32"))
    }

    @Test func aLineOfAFileWhoseNameOnlyOpensAnExemptNameIsReported() {
        #expect(!Self.sampleRule.exempts("\(Self.sampleExemptFile)Extra.swift:32"))
    }

    @Test func theScanFindsAForbiddenNameInAListOfLines() {
        let lines = [
            "import Foundation",
            "let handle = FileHandle.standardOutput",
            "let text = \"no forbidden name here\""
        ]

        #expect(SwiftSourceScan.lineNumbers(in: lines, matching: Self.fileHandleRule.isBroken) == [2])
    }

    @Test func aLineThatNamesTheRuleIsBrokenByIt() {
        #expect(Self.fileHandleRule.isBroken(by: "case .output: FileHandle.standardOutput"))
    }

    @Test func aLineThatNamesNoRuleIsNotBrokenByIt() {
        #expect(!Self.fileHandleRule.isBroken(by: "StandardStream.output.write(line: text)"))
    }

    /// Finds each line of this package's source that breaks `rule`, the
    /// exempt files included.
    ///
    /// - Parameter rule: The rule to read each line against.
    /// - Returns: One text for each reported line, in the form
    ///   `<path>:<line number>`.
    /// - Throws: The error of the walk, when a file is unreadable or when the
    ///   directory holds no Swift file.
    private static func reportedLines(of rule: Rule) throws -> [String] {
        try SwiftSourceScan.reportedLines(inDirectory: sourcesPath, matching: rule.isBroken)
    }
}
