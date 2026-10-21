import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsAgents

/// Pins the `GraphQLEndpointTool` conformance of the `agents` tool (AG-8b,
/// EXTRAS-9 rule 1 and rule 11).
///
/// The tool gives one endpoint, the `agents` endpoint (``AgentsGraph``), over
/// the registry of its runner. The registry makes that endpoint one time, thus
/// each tool over one registry gives the same instance. A host finds the
/// endpoint with `tool as? any GraphQLEndpointTool`.
@Suite("The agents tool is a GraphQLEndpointTool")
struct AgentsToolEndpointTests {
    /// The agent of the layer before a reload.
    private static let coder = "coder"

    /// The agent that a test adds before a reload.
    private static let extra = "extra"

    /// The version of the schema of the endpoint.
    private static let version = "1"

    /// The grants of a tool. Each grant gives the endpoint.
    private static let grants: [AgentsToolContext.Grant] = [.full, .messagingOnly]

    /// Makes a layer that holds ``coder``.
    ///
    /// - Returns: The layer. The test deletes it.
    /// - Throws: The error of the file system.
    private static func makeLayer() throws -> TemporaryLayer {
        try TemporaryLayer.make(holding: [AgentDocumentPath.of(coder): AgentFolderFixture.agentText(name: coder)])
    }

    /// Casts `tool` to `GraphQLEndpointTool` as a host does, and reads its one
    /// endpoint.
    ///
    /// - Parameter tool: The tool, as a host holds it.
    /// - Returns: The one endpoint of the tool.
    /// - Throws: A failed requirement when the cast fails, or when the tool
    ///   does not give exactly one endpoint.
    private static func endpoint(of tool: any Tool) throws -> any GraphQLEndpoint {
        let endpointTool = try #require(tool as? any GraphQLEndpointTool)
        let endpoints = endpointTool.graphQLEndpoints
        try #require(endpoints.count == 1, "the agents tool gives one endpoint, not \(endpoints.count)")
        return endpoints[0]
    }

    /// Reads the ids of the `agents` query through `endpoint`.
    ///
    /// - Parameter endpoint: The endpoint.
    /// - Returns: The ids, in the order of the response.
    /// - Throws: The fault of the endpoint, or a failed requirement when the
    ///   response holds no list of agents.
    private static func agentIDs(through endpoint: any GraphQLEndpoint) async throws -> [String] {
        let reply = try GraphQLReply(
            await endpoint.execute(query: "{ agents { id } }", variables: [:], operationName: nil, viewer: nil))
        return try reply.objects("agents").compactMap { $0["id"] as? String }
    }

    @Test("the tool gives the agents endpoint with its name, version and scope, for each grant", arguments: grants)
    func toolGivesTheEndpoint(grant: AgentsToolContext.Grant) async throws {
        let layer = try Self.makeLayer()
        defer { try? layer.delete() }
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]), grant: grant)
        defer { try? harness.delete() }

        let endpoint = try Self.endpoint(of: harness.tool)

        #expect(endpoint.name == AgentsGraph.endpointName)
        #expect(endpoint.version == Self.version)
        #expect(endpoint.scope == .sessionFolder)
    }

    @Test("a made tool, held as any Tool, casts to GraphQLEndpointTool")
    func madeToolCastsToGraphQLEndpointTool() async throws {
        let layer = try Self.makeLayer()
        defer { try? layer.delete() }
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }
        let tool: any Tool = harness.tool

        #expect(tool as? any GraphQLEndpointTool != nil)
    }

    @Test("two tools made over one registry give the identical endpoint")
    func twoToolsGiveOneEndpoint() async throws {
        let layer = try Self.makeLayer()
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer])
        let first = try await AgentsToolHarness.make(registry: registry)
        defer { try? first.delete() }
        let second = try await AgentsToolHarness.make(registry: registry, grant: .messagingOnly)
        defer { try? second.delete() }

        let firstEndpoint = try #require(try Self.endpoint(of: first.tool) as? AgentsGraph)
        let secondEndpoint = try #require(try Self.endpoint(of: second.tool) as? AgentsGraph)

        #expect(firstEndpoint === secondEndpoint)
    }

    @Test("after a reload, the endpoint of the tool and list agents both give the new agent")
    func endpointAndListAgentsFollowOneReload() async throws {
        let layer = try Self.makeLayer()
        defer { try? layer.delete() }
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }
        let endpoint = try Self.endpoint(of: harness.tool)

        try layer.write(AgentFolderFixture.agentText(name: Self.extra), at: AgentDocumentPath.of(Self.extra))
        try await harness.runHarness.registry.reload()

        #expect(try await Self.agentIDs(through: endpoint) == [Self.coder, Self.extra])
        #expect(try await harness.call("list agents").contains(Self.extra))
    }

    @Test("the endpoint of a registry does not keep the registry")
    func endpointDoesNotKeepTheRegistry() async throws {
        let layer = try Self.makeLayer()
        defer { try? layer.delete() }
        var registry: AgentRegistry? = AgentRegistry(layers: [layer.layer])
        weak let released = registry
        try await registry?.load()
        let endpoint = try #require(try registry?.agentsGraph())

        registry = nil

        #expect(released == nil)
        #expect(try await Self.agentIDs(through: endpoint) == [Self.coder])
    }
}
