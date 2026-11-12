import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the `tools.agents.enabled` value of the render of an agent body: it
/// tells the tools of that agent, not only the tools of the session.
///
/// Seen live in the bench run oneplan24: the house-rules partial
/// (`{% if tools.agents.enabled %}` … `schedule agent`) rendered in the
/// planner and the double-check agents, whose frontmatter has
/// `disallowedTools: [agents]`, because the value came from the session
/// configuration alone.
@Suite("The tool template values of an agent")
struct AgentToolTemplateTests {
    /// The shared runner of the main-session instructions tests.
    private typealias Fixture = SessionInstructionsFixture

    /// The id of the agent with `disallowedTools: [agents]`.
    private static let plannerID = "planner"

    /// The id of the agent with no `disallowedTools` key.
    private static let coderID = "coder"

    /// The body: one line for the agents group, one for the kanban group.
    private static let gatedBody = """
        {% if tools.agents.enabled %}schedule an agent{% endif %}|\
        {% if tools.kanban.enabled %}use the board{% endif %}
        """

    /// The session template context: the agents group and the kanban group
    /// are on.
    private static let sessionContext: [String: TemplateValue] = [
        "tools": .dictionary([
            "agents": .dictionary(["enabled": .bool(true)]),
            "kanban": .dictionary(["enabled": .bool(true)])
        ])
    ]

    /// Renders the body of `agentID` from a layer with the two agents, with
    /// `context`.
    ///
    /// - Parameters:
    ///   - agentID: The agent.
    ///   - context: The session template context.
    /// - Returns: The rendered body.
    private static func body(
        of agentID: String, context: [String: TemplateValue] = sessionContext
    ) async throws -> String {
        let layer = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: plannerID): """
                ---
                name: \(plannerID)
                description: Plans the work.
                disallowedTools: [agents]
                ---
                \(gatedBody)
                """,
            AgentFolderFixture.documentPath(of: coderID): AgentFolderFixture.agentText(
                name: coderID, body: gatedBody)
        ])
        defer { try? layer.delete() }
        let made = try await Fixture.makeRunner(
            registry: AgentRegistry(layers: [layer.layer], templateContext: context))
        defer { try? made.harness.delete() }
        let definition = try #require(made.harness.registry.catalog().definition(named: agentID))
        return try await made.runner.sessionAgentInstructions(for: definition).body
    }

    @Test("an agent with disallowedTools [agents] renders with tools.agents.enabled false, and other groups stay")
    func aDisallowedAgentsGroupIsOff() async throws {
        #expect(try await Self.body(of: Self.plannerID) == "|use the board")
    }

    @Test("an agent that does not disallow the agents tool keeps the value of the session")
    func anAllowedAgentsGroupStays() async throws {
        #expect(try await Self.body(of: Self.coderID) == "schedule an agent|use the board")
    }

    @Test("an agents group that the session turns off stays off")
    func anOffAgentsGroupStaysOff() async throws {
        let off: [String: TemplateValue] = [
            "tools": .dictionary(["agents": .dictionary(["enabled": .bool(false)])])
        ]
        #expect(try await Self.body(of: Self.coderID, context: off) == "|")
    }
}
