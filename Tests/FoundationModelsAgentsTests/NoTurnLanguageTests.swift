import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsAgents

/// Guards the rule of the user for each text that the model reads: no
/// turns. The model never reads "end your", "when you end", "turn",
/// "starts you" or "write no text" (``TurnLanguage``).
///
/// The suite reads the texts of the `agents` tool that the model gets, and it
/// also walks each string literal of each Swift file under `Sources/`. Thus a
/// new text with turn language fails the walk before any model reads it. A
/// comment line is not a text for the model, thus the walk passes over it.
@Suite("No turn language")
struct NoTurnLanguageTests {
    /// The source directory, relative to the package root.
    private static let sourcesPath = "Sources"

    @Test(arguments: [
        "Your final message goes to that session when you end.",
        "The run stops when its turn ends.",
        "End your answer now.",
        "The mail starts you working again.",
        "Write no text.",
        "Wait for your next TURN."
    ])
    func aTextWithTurnLanguageIsReported(text: String) {
        #expect(!TurnLanguage.phrases(in: text).isEmpty)
    }

    @Test(arguments: [
        "The run stops soon.",
        "Return the result.",
        "the agent used more passes than its maxTurns limit",
        "Go on with your work."
    ])
    func aTextWithNoTurnLanguageIsNotReported(text: String) {
        #expect(TurnLanguage.phrases(in: text).isEmpty)
    }

    @Test func theLiteralTextOfALineIsTheTextBetweenItsQuotes() {
        let lines = [
            "/// The answer when your turn ends.",
            "let turns = \"no turn here\" + \"a \\\"quoted\\\" word\"",
            "static let text = \"\"\"",
            "    The text of a turn.",
            "    \"\"\"",
            "let after = turns.count"
        ]

        #expect(
            TurnLanguage.literalText(of: lines)
                == ["", "no turn here a quoted word", "", "    The text of a turn.", "    ", ""])
    }

    @Test func noStringLiteralUnderSourcesHoldsTurnLanguage() throws {
        let offenders = try SwiftSourceScan.reportedLines(inDirectory: Self.sourcesPath) { lines in
            SwiftSourceScan.lineNumbers(of: TurnLanguage.literalText(of: lines).map {
                !TurnLanguage.phrases(in: $0).isEmpty
            })
        }

        #expect(
            offenders.isEmpty,
            """
            No string literal under Sources/ may hold turn language (\(TurnLanguage.bannedPhrases), \
            \(TurnLanguage.bannedWords)); found: \(offenders.joined(separator: ", "))
            """)
    }

    @Test func theTextsOfTheAgentsToolHoldNoTurnLanguage() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }
        let operationTexts = harness.tool.operationTool.operationDescriptors.flatMap { operation in
            [operation.description] + operation.parameters.map(\.description)
        }
        let texts = [
            harness.tool.description, AgentsToolDescription.messaging, AgentsToolText.messageSentToCaller,
            harness.tool.collectInstruction(
                forCompletionToken: "01M3N00000000000000000TOKN", describing: "agent code-reviewer: a task")
        ] + operationTexts

        #expect(texts.allSatisfy { TurnLanguage.phrases(in: $0).isEmpty }, "The texts were: \(texts)")
    }
}
