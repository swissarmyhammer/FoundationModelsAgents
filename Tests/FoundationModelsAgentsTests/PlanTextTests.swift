import Foundation
import Testing

/// Holds the text of `plan.md` to the code.
///
/// The rule table of `AgentDefinition` (§4.3) gives a warning for a `name`
/// that is absent or not equal to the file name, and the file loads, because
/// the file name is the id. A `description` that is absent or empty is also a
/// warning. Thus the tier table of §4.2 must not state that these keys are
/// required. `AgentRunner.start` is `async throws(AgentRunnerError)`
/// and `AgentRun.result()` is `async throws`, thus the fan-out example of
/// §9.3 writes `try await`.
@Suite("plan.md text")
struct PlanTextTests {
    /// The path of the plan, relative to the package root.
    private static let planPath = "plan.md"

    /// Every text that the plan must hold.
    private static let claims = [
        "`name` (a warning when absent or not equal to the file name; the file name is the id)",
        "`description` (a warning when absent or empty; the agent is then not model-visible)",
        "`async let a = try await runner.start(\"code-reviewer\", prompt: p1).result()`",
        "`let reviewA = try await a`"
    ]

    /// Each text that the plan must not hold.
    private static let removedTexts = [
        "`name`, `description` (required)",
        "`async let a = runner.start("
    ]

    @Test(arguments: claims)
    func thePlanMakesTheClaim(claim: String) throws {
        let text = try Self.readPlan()

        #expect(text.contains(claim), "plan.md must state \"\(claim)\"")
    }

    @Test(arguments: removedTexts)
    func thePlanDoesNotHoldTheRemovedText(removed: String) throws {
        let text = try Self.readPlan()

        #expect(!text.contains(removed), "plan.md must not state \"\(removed)\"")
    }

    /// Reads the plan.
    ///
    /// - Returns: The text of `plan.md`.
    /// - Throws: An error when the plan is not readable UTF-8 text.
    private static func readPlan() throws -> String {
        try String(contentsOf: PackageRoot.directory.appendingPathComponent(planPath), encoding: .utf8)
    }
}
