import Foundation
import Testing

/// Holds the text of `README.md` to the rules of the code.
///
/// The rule table of `AgentDefinition` gives a warning for a `name` that is
/// absent or not equal to the folder name, and the agent loads, because the
/// folder name is the id. The README must state this rule, and it must not
/// state that `name` is necessary. A page wraps its lines, thus each claim
/// fits on one line of the README.
@Suite("README.md text")
struct ReadmeTextTests {
    /// Every text that the README must hold.
    private static let claims = [
        "A `name` that is absent or not equal to the folder name gives a warning.",
        "The agent loads, because the folder name is the id.",
        "An agent with no valid `description` is not visible to the model."
    ]

    /// The text that makes `name` a key that each file must have.
    private static let necessaryNameText = "`name` and `description` are necessary"

    @Test(arguments: claims)
    func theReadmeMakesTheClaim(claim: String) throws {
        let text = try Self.readReadme()

        #expect(text.contains(claim), "README.md must state \"\(claim)\"")
    }

    @Test func theReadmeDoesNotStateThatNameIsNecessary() throws {
        let text = try Self.readReadme()

        #expect(!text.contains(Self.necessaryNameText), "a file with no `name` loads with a warning")
    }

    /// Reads the README.
    ///
    /// - Returns: The text of the README.
    /// - Throws: An error when the README is not readable UTF-8 text.
    private static func readReadme() throws -> String {
        try String(contentsOf: ReadmeExample.readmeURL, encoding: .utf8)
    }
}
