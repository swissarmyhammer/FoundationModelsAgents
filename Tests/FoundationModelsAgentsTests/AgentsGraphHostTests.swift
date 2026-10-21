import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the `agents` endpoint of a registry as public API (AG-8b): a host
/// gets the one endpoint of its registry with no `agents` tool.
///
/// This file imports the library without `@testable`, as a host does. Thus
/// each call here compiles only against the public API of the library.
@Suite("A host gets the agents endpoint of its registry")
struct AgentsGraphHostTests {
    /// The agent of the layer.
    private static let coder = "coder"

    @Test("a host reads the catalog of its registry through the endpoint of the registry")
    func hostReadsTheCatalogThroughTheEndpoint() async throws {
        let layer = try TemporaryLayer.make(holdingAgent: Self.coder)
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer])
        try await registry.load()

        let endpoint: any GraphQLEndpoint = try registry.agentsGraph()
        let reply = try GraphQLReply(
            await endpoint.execute(query: "{ agents { id } }", variables: [:], operationName: nil, viewer: nil))

        #expect(try reply.objects("agents").compactMap { $0["id"] as? String } == [Self.coder])
    }

    @Test("each call of a host gives the one endpoint of the registry")
    func eachCallGivesTheOneEndpoint() throws {
        let layer = try TemporaryLayer.make(holdingAgent: Self.coder)
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer])

        #expect(try registry.agentsGraph() === registry.agentsGraph())
    }
}
