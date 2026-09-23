import Testing

/// Guards the layer stack of `FoundationModelsExtras`: this package adds
/// nothing to `DotfolderStack`. Extras gives `public init(layers:)`, and each
/// shared step of the stack belongs in Extras, not in a consumer.
///
/// A local extension that declares an initializer of Extras again gives each
/// call site two initializers of one signature, and the build can then stop
/// with an ambiguous use error.
///
/// The suite gives `SwiftSourceScan` the test of a line below, and that reader
/// walks each Swift file under `Sources/`. A line declares the extension when
/// it holds the text `extension DotfolderStack` and the character after that
/// text is not a letter or a digit. Thus `extension DotfolderStackFixture` is
/// not reported, and a call of the initializer is not reported. A comment line
/// holds no code, thus the walk passes over it, as the other guard suites do.
@Suite("No DotfolderStack extension")
struct NoDotfolderStackExtensionTests {
    /// The text that opens an extension of the layer stack.
    private static let extensionMarker = "extension DotfolderStack"

    /// The source directory, relative to the package root.
    private static let sourcesPath = "Sources"

    @Test(arguments: [
        "extension DotfolderStack {",
        "internal extension DotfolderStack.Layer {",
        "extension DotfolderStack: CustomStringConvertible {",
        "extension DotfolderStack"
    ])
    func aLineThatOpensTheExtensionIsReported(line: String) {
        #expect(Self.declaresADotfolderStackExtension(line))
    }

    @Test(arguments: [
        "let stack = DotfolderStack(layers: layers)",
        "extension DotfolderStackFixture {",
        "extension DotfolderStack2 {",
        "extension AgentRegistry {",
        "/// Do not write `extension DotfolderStack {` in this package.",
        "    // extension DotfolderStack {"
    ])
    func aLineThatOpensNoSuchExtensionIsNotReported(line: String) {
        #expect(!Self.declaresADotfolderStackExtension(line))
    }

    @Test func theRuleFindsTheExtensionInAListOfLines() {
        let lines = [
            "import FoundationModelsExtras",
            "/// extension DotfolderStack {",
            "extension DotfolderStack {",
            "}"
        ]

        #expect(SwiftSourceScan.lineNumbers(in: lines, matching: Self.declaresADotfolderStackExtension) == [3])
    }

    @Test func noFileUnderSourcesExtendsTheLayerStack() throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.sourcesPath, matching: Self.declaresADotfolderStackExtension)

        #expect(
            offenders.isEmpty,
            """
            No file under Sources/ may extend DotfolderStack. Extras gives \
            public init(layers:); found: \(offenders.joined(separator: ", "))
            """)
    }

    /// Tells whether `line` opens an extension of `DotfolderStack` itself.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line is not a comment, the line holds the
    ///   marker, and no letter and no digit comes after the marker.
    private static func declaresADotfolderStackExtension(_ line: String) -> Bool {
        !SwiftSourceScan.isComment(line)
            && line.components(separatedBy: extensionMarker).dropFirst().contains { textAfterMarker in
                textAfterMarker.first.map { !$0.isLetter && !$0.isNumber } ?? true
            }
    }
}
