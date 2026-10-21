import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import GraphQL

/// An `agents` endpoint over a registry of temporary layers, for the suite
/// of the endpoint.
///
/// `make(layers:)` loads the registry before it makes the endpoint, as a
/// host does. The test owns the layers, and deletes them in a `defer`.
struct AgentsGraphFixture {
    // MARK: - Documents

    /// The fields of an `AgentDiagnostic` that each document selects.
    static let diagnosticFields = "{ code severity agent path layerRoot message }"

    /// The fields of an `Agent` that each document selects.
    static let agentFields = """
        { id description model color background isModelVisible isUserInvocable isDefault \
        layer { name root } marketplace { id sha } diagnostics \(diagnosticFields) }
        """

    /// The query of each agent of the catalog.
    static let agentsQuery = "{ agents \(agentFields) }"

    /// The query of one agent by its id.
    static let agentQuery = "query($id: ID!) { agent(id: $id) \(agentFields) }"

    /// The query of each diagnostic of the catalog.
    static let diagnosticsQuery = "{ diagnostics \(diagnosticFields) }"

    // MARK: - The objects

    /// The endpoint.
    let graph: AgentsGraph

    /// Makes a registry over `layers`, loads it, and makes the endpoint.
    ///
    /// - Parameter layers: The layers of the registry, lowest precedence
    ///   first.
    /// - Returns: The fixture.
    /// - Throws: The error of the load, or of the schema build.
    static func make(layers: [DotfolderStack.Layer]) async throws -> AgentsGraphFixture {
        try await make(registry: AgentRegistry(layers: layers))
    }

    /// Loads `registry`, and makes the endpoint over it.
    ///
    /// - Parameter registry: The registry of the endpoint.
    /// - Returns: The fixture.
    /// - Throws: The error of the load, or of the schema build.
    static func make(registry: AgentRegistry) async throws -> AgentsGraphFixture {
        try await registry.load()
        return AgentsGraphFixture(graph: try AgentsGraph(registry: registry))
    }

    // MARK: - Calls

    /// Runs one document against the endpoint with no viewer.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - variables: The values of its variables.
    /// - Returns: The parsed response.
    /// - Throws: The fault of the endpoint, or a failed requirement when the
    ///   response is not a JSON object.
    func run(_ document: String, variables: [String: Map] = [:]) async throws -> GraphQLReply {
        try await Self.run(document, variables: variables, on: graph)
    }

    /// Reads one agent by its id.
    ///
    /// - Parameter id: The id that the call gives.
    /// - Returns: The parsed response.
    /// - Throws: What ``run(_:variables:)`` throws.
    func agent(_ id: String) async throws -> GraphQLReply {
        try await run(Self.agentQuery, variables: ["id": .string(id)])
    }

    /// Runs one document against an endpoint with no viewer.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - variables: The values of its variables.
    ///   - graph: The endpoint.
    /// - Returns: The parsed response.
    /// - Throws: The fault of the endpoint, or a failed requirement when the
    ///   response is not a JSON object.
    static func run(
        _ document: String, variables: [String: Map] = [:], on graph: AgentsGraph
    ) async throws -> GraphQLReply {
        try GraphQLReply(await graph.execute(query: document, variables: variables, operationName: nil, viewer: nil))
    }
}
