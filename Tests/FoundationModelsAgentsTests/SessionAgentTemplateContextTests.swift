import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins ``AgentRunner/sessionAgentInstructions(for:templateContext:)``: the
/// body of the agent, and each partial of the body, renders with the given
/// template context in place of the context of the registry.
///
/// The host gives the values of the tool selection of the agent, thus a body
/// that reads `tools.<group>.enabled` sees the tools that the model has.
@Suite("Session agent template context")
struct SessionAgentTemplateContextTests {
    /// The shared runner of the main-session instructions tests.
    private typealias Fixture = SessionInstructionsFixture

    /// The id of the agent of each row.
    private static let agentID = AgentFolderFixture.helperID

    /// A body that tells if the shell group is on.
    private static let gatedText = "{% if tools.shell.enabled %}shell on{% else %}shell off{% endif %}"

    /// Gives a template context with the shell group on or off.
    ///
    /// - Parameter enabled: The value of `tools.shell.enabled`.
    /// - Returns: The context.
    private static func shellContext(enabled: Bool) -> [String: TemplateValue] {
        ["tools": .dictionary(["shell": .dictionary(["enabled": .bool(enabled)])])]
    }

    /// Renders the body of the agent of `files` with a registry whose context
    /// turns the shell group on.
    ///
    /// - Parameters:
    ///   - files: The files of the layer, by their path relative to its root.
    ///   - context: The context to give, or `nil` to call
    ///     `sessionAgentInstructions(for:)`.
    /// - Returns: The rendered body.
    private static func body(
        of files: [String: String], context: [String: TemplateValue]?
    ) async throws -> String {
        let layer = try TemporaryLayer.make(holding: files)
        defer { try? layer.delete() }
        let made = try await Fixture.makeRunner(
            registry: AgentRegistry(layers: [layer.layer], templateContext: shellContext(enabled: true)))
        defer { try? made.harness.delete() }
        let definition = try #require(made.harness.registry.catalog().definition(named: agentID))
        guard let context else {
            return try await made.runner.sessionAgentInstructions(for: definition).body
        }
        return try await made.runner.sessionAgentInstructions(for: definition, templateContext: context).body
    }

    /// The files of a layer whose agent has the gated body.
    private static let gatedAgent = [
        AgentFolderFixture.documentPath(of: agentID): AgentFolderFixture.agentText(name: agentID, body: gatedText)
    ]

    @Test("the given context turns the shell group off, and the registry context has no effect")
    func theGivenContextTurnsTheGroupOff() async throws {
        #expect(try await Self.body(of: Self.gatedAgent, context: Self.shellContext(enabled: false)) == "shell off")
    }

    @Test("the given context turns the shell group on")
    func theGivenContextTurnsTheGroupOn() async throws {
        #expect(try await Self.body(of: Self.gatedAgent, context: Self.shellContext(enabled: true)) == "shell on")
    }

    @Test("an empty given context replaces the registry context")
    func anEmptyGivenContextReplacesTheRegistryContext() async throws {
        #expect(try await Self.body(of: Self.gatedAgent, context: [:]) == "shell off")
    }

    @Test("sessionAgentInstructions(for:) renders with the registry context")
    func theDefaultFormUsesTheRegistryContext() async throws {
        #expect(try await Self.body(of: Self.gatedAgent, context: nil) == "shell on")
    }

    @Test("a partial of the body renders with the given context")
    func aPartialSeesTheGivenContext() async throws {
        let files = [
            AgentFolderFixture.documentPath(of: Self.agentID): AgentFolderFixture.includingAgentText(name: Self.agentID),
            AgentFolderFixture.partialPath(in: nil): Self.gatedText
        ]

        #expect(try await Self.body(of: files, context: Self.shellContext(enabled: false)) == "shell off")
    }
}
