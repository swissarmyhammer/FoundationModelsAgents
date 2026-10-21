import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// The diagnostics of the `agents` GraphQL endpoint (AG-8, APP-12): the
/// findings of the load of the catalog, each with an `UPPER_SNAKE` code, on
/// the agent that they name and in the root `diagnostics` list.
@Suite("Agents graph diagnostics")
struct AgentsGraphDiagnosticTests {
    /// Tells whether a code has the `UPPER_SNAKE` form of EXTRAS-9 rule 8:
    /// words of capital letters, with `_` between them.
    ///
    /// - Parameter code: The code.
    /// - Returns: `true` for a code in `UPPER_SNAKE`.
    static func isUpperSnake(_ code: String) -> Bool {
        code.wholeMatch(of: /[A-Z]+(_[A-Z]+)*/) != nil
    }

    /// The `AgentDiagnosticSeverity` of a warning.
    private static let warning = "WARNING"

    /// The `AgentDiagnosticSeverity` of a skip.
    private static let skip = "SKIP"

    /// The `AgentDiagnosticSeverity` of an advisory.
    private static let advisory = "ADVISORY"

    /// An agent file with no `description` key.
    private static let undescribedAgent = """
        ---
        name: \(AgentFolderFixture.helperID)
        ---

        \(AgentFolderFixture.body)
        """

    /// The path of the placeholder of the document of
    /// ``AgentFolderFixture/helperID``.
    private static let placeholderPath =
        "\(AgentFolderFixture.helperID)/\(AgentFolderFixture.documentPlaceholderName)"

    /// The path of the `default/` agent folder that a root `AGENT.md` hides.
    private static let defaultFolderPath = AgentFolderFixture.documentPath(of: AgentFolderFixture.defaultAgentID)

    /// Each code of a diagnostic has the `UPPER_SNAKE` form of EXTRAS-9
    /// rule 8.
    @Test(arguments: AgentDiagnostic.Code.allCases)
    func eachCodeIsUpperSnake(code: AgentDiagnostic.Code) {
        #expect(Self.isUpperSnake(code.rawValue))
    }

    /// An agent with no description gives `MISSING_DESCRIPTION` on the agent
    /// and in the root list, with the file and the layer of the agent.
    @Test func aMissingDescriptionGivesItsCode() async throws {
        let layer = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: AgentFolderFixture.helperID): Self.undescribedAgent
        ])
        defer { try? layer.delete() }
        let fixture = try await AgentsGraphFixture.make(layers: [layer.layer])

        let agent = try await fixture.agent(AgentFolderFixture.helperID).object("agent")
        let onAgent = try #require(agent["diagnostics"] as? [[String: Any]])
        let root = try await fixture.run(AgentsGraphFixture.diagnosticsQuery).objects("diagnostics")
        let diagnostic = try #require(onAgent.first)

        #expect(onAgent.map { $0["code"] as? String } == ["MISSING_DESCRIPTION"])
        #expect(diagnostic["severity"] as? String == Self.warning)
        #expect(diagnostic["agent"] as? String == AgentFolderFixture.helperID)
        #expect(
            diagnostic["path"] as? String
                == layer.root.appendingPathComponent(AgentFolderFixture.documentPath(of: AgentFolderFixture.helperID))
                .path)
        #expect(diagnostic["layerRoot"] as? String == layer.root.path)
        #expect(root.map { $0["code"] as? String } == ["MISSING_DESCRIPTION"])
    }

    /// A placeholder of an agent document gives `NOT_LOCAL` in the root
    /// list. The agent does not load, thus no agent holds the diagnostic.
    @Test func aPlaceholderGivesNotLocal() async throws {
        let layer = try TemporaryLayer.make(holding: [Self.placeholderPath: ""])
        defer { try? layer.delete() }
        let fixture = try await AgentsGraphFixture.make(layers: [layer.layer])

        let root = try await fixture.run(AgentsGraphFixture.diagnosticsQuery).objects("diagnostics")
        let agents = try await fixture.run(AgentsGraphFixture.agentsQuery).objects("agents")

        #expect(root.map { $0["code"] as? String } == ["NOT_LOCAL"])
        #expect(root.map { $0["severity"] as? String } == [Self.skip])
        #expect(root.map { $0["agent"] as? String } == [AgentFolderFixture.helperID])
        #expect(agents.isEmpty)
    }

    /// Two layers that hold one id give `HIDDEN_COPY` on the agent of the
    /// higher layer: the lower copy is hidden.
    @Test func aCopyThatAHigherLayerHidesGivesHiddenCopy() async throws {
        let lower = try AgentsGraphTests.makeLayer(ids: [AgentFolderFixture.helperID])
        defer { try? lower.delete() }
        let higher = try AgentsGraphTests.makeLayer(ids: [AgentFolderFixture.helperID])
        defer { try? higher.delete() }
        let fixture = try await AgentsGraphFixture.make(layers: [lower.userLayer, higher.layer])

        let agent = try await fixture.agent(AgentFolderFixture.helperID).object("agent")
        let diagnostics = try #require(agent["diagnostics"] as? [[String: Any]])

        #expect(diagnostics.map { $0["code"] as? String } == ["HIDDEN_COPY"])
        #expect(diagnostics.map { $0["severity"] as? String } == [Self.advisory])
    }

    /// A `default/` agent folder beside the root `AGENT.md` of one layer
    /// gives `DUPLICATE_DEFAULT` on the default agent.
    @Test func aDefaultFolderBesideTheRootDocumentGivesDuplicateDefault() async throws {
        let layer = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName),
            Self.defaultFolderPath: AgentFolderFixture.agentText(name: AgentFolderFixture.defaultAgentID),
        ])
        defer { try? layer.delete() }
        let fixture = try await AgentsGraphFixture.make(layers: [layer.userLayer])

        let agent = try await fixture.agent(AgentFolderFixture.defaultAgentID).object("agent")
        let diagnostics = try #require(agent["diagnostics"] as? [[String: Any]])

        #expect(diagnostics.map { $0["code"] as? String } == ["DUPLICATE_DEFAULT"])
        #expect(diagnostics.map { $0["severity"] as? String } == [Self.warning])
    }
}
