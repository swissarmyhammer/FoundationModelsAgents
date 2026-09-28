import Foundation
import Testing

/// Holds each document and each doc comment to the run model of plan.md §8
/// and §9.2.
///
/// `start agent` is a background run. The final message of the run is the
/// detail of the Router run, and it comes to the calling session as mail. The
/// pump of the Router delivers the mail, and a run ends when its session is
/// idle. No text may name the parts of a model that the package does not
/// use: a host or a run that dispatches the next prompt, a queued prompt, a
/// turn only for delivery or for a final answer, a run that posts its final
/// message, a generation gate, or a settle grace of the tool.
@Suite("Run model wording")
struct RunModelWordingTests {
    /// One phrase that one document must not hold.
    struct Row: Sendable, CustomTestStringConvertible {
        /// The path of the document, relative to the package root.
        let document: String

        /// The phrase, in lowercase.
        let phrase: String

        /// The name of the row in the test report.
        var testDescription: String {
            "\(document): \(phrase)"
        }
    }

    /// The directory of the library source, relative to the package root.
    private static let sourceDirectory = "Sources"

    /// The phrases of the removed run model, in lowercase. The check reads
    /// each text in lowercase, thus "Delivery turn" and "child-delivery turn"
    /// match too.
    private static let removedPhrases = [
        "dispatchnextprompt",
        "enqueue(prompt:)",
        "cancelcurrentturn",
        "delivery turn",
        "final-answer",
        "inlinesettlegrace",
        "posts its final message",
        "generation gate"
    ]

    /// The documents outside the DocC catalog, relative to the package root.
    private static let plainDocuments = ["plan.md", "README.md", "docs/skills-and-agents.md"]

    /// Each document: the plain documents, then each page of the DocC
    /// catalog.
    private static let documents = plainDocuments + DocumentationTests.pages.map { page in
        "\(DocumentationTests.catalogPath)/\(page)\(DocumentationTests.pageSuffix)"
    }

    /// One row for each document and each removed phrase.
    private static let rows = documents.flatMap { document in
        removedPhrases.map { Row(document: document, phrase: $0) }
    }

    @Test(arguments: rows)
    func noDocumentNamesTheRemovedRunModel(row: Row) throws {
        let url = PackageRoot.directory.appendingPathComponent(row.document)
        let text = try String(contentsOf: url, encoding: .utf8).lowercased()

        #expect(!text.contains(row.phrase), "\(row.document) must not say \"\(row.phrase)\"")
    }

    @Test(arguments: removedPhrases)
    func noSourceLineNamesTheRemovedRunModel(phrase: String) throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.sourceDirectory, matching: { line in line.lowercased().contains(phrase) })

        #expect(offenders.isEmpty, "these lines say \"\(phrase)\": \(offenders.joined(separator: ", "))")
    }
}
