import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import GraphQL
import Testing

/// The `agents` GraphQL endpoint (AG-8, EXTRAS-9): the contract of the
/// endpoint, and the `agents` and `agent(id:)` queries over the catalog of
/// one registry.
///
/// Each test writes its agents into a ``TemporaryLayer`` and reads them
/// through ``AgentsGraphFixture``.
@Suite("Agents graph")
struct AgentsGraphTests {
    // MARK: - Constants

    /// The name of the golden file of the schema, under `Tests/Fixtures`.
    private static let goldenFileName = "agents.graphql"

    /// The folder of the golden files, relative to the package root.
    private static let goldenFolder = "Tests/Fixtures"

    /// The id of a second agent next to ``AgentFolderFixture/helperID``.
    private static let reviewerID = "reviewer"

    /// An id that no agent has.
    private static let unknownID = "nobody"

    /// A valid agent id of digits only, which an Int literal also names.
    private static let decimalID = "42"

    /// The `model` value of the agent with each key.
    private static let model = "flash"

    /// The `color` value of the agent with each key.
    private static let color = "blue"

    /// The `AgentLayerName` of a project layer.
    private static let projectLayerName = "PROJECT"

    /// The `AgentLayerName` of a user layer.
    private static let userLayerName = "USER"

    /// The `AgentLayerName` of a marketplace layer.
    private static let marketplaceLayerName = "MARKETPLACE"

    /// The op of the `list agents` operation of the `agents` tool.
    private static let listOperation = "list agents"

    /// The code of the error before the first load of the registry.
    private static let catalogNotLoadedCode = "CATALOG_NOT_LOADED"

    /// The text of an agent file with each key that the `Agent` type gives:
    /// the model cannot see it, and it is not a slash command.
    private static let agentWithEachKey = """
        ---
        name: \(AgentFolderFixture.helperID)
        description: \(AgentFolderFixture.description)
        model: \(model)
        color: \(color)
        background: true
        disable-model-invocation: true
        user-invocable: false
        ---

        \(AgentFolderFixture.body)
        """

    // MARK: - The endpoint contract

    /// The endpoint has the name `agents`, the version `1`, the scope of the
    /// session folder, an SDL schema that builds, the response conventions
    /// of the toolkit and each rule of EXTRAS-9 with no exception, and it
    /// rewrites the alias `agent(name:)` to `agent(id:)`.
    ///
    /// The probe of the conformance check runs through `execute`, which
    /// cannot start a subscription. Thus the alias `agentChanges` of the
    /// subscription has its own test through `subscribe`, in
    /// `AgentsGraphChangesTests`.
    @Test func theEndpointConforms() async throws {
        let layer = try Self.makeLayer(ids: [AgentFolderFixture.helperID])
        defer { try? layer.delete() }
        let fixture = try await AgentsGraphFixture.make(layers: [layer.layer])
        let probe = GraphQLAliasProbe(
            query: "{ agent(name: \"\(AgentFolderFixture.helperID)\") { id } }", from: "name", to: "id")

        let problems = await GraphQLEndpointConformance.problems(
            of: fixture.graph, scope: .sessionFolder, probe: probe, codes: AgentsGraphError.codes)

        #expect(problems.isEmpty)
        #expect(fixture.graph.name == "agents")
        #expect(fixture.graph.version == "1")
    }

    /// Each type, field, argument and enum value of the schema has a
    /// description, because a client learns the schema with introspection.
    @Test func eachPartOfTheSchemaHasADescription() async throws {
        let fixture = try await AgentsGraphFixture.make(layers: [])

        let undescribed = try GraphQLSchemaDescriptions.undescribed(in: buildSchema(source: fixture.graph.schema))

        #expect(undescribed.isEmpty)
    }

    /// The SDL schema is the schema in the golden file.
    @Test func theSchemaMatchesTheGoldenFile() async throws {
        let fixture = try await AgentsGraphFixture.make(layers: [])
        let goldenFile = PackageRoot.directory
            .appendingPathComponent(Self.goldenFolder)
            .appendingPathComponent(Self.goldenFileName)

        #expect(GraphQLSchemaGolden.problems(of: fixture.graph.schema, against: goldenFile).isEmpty)
    }

    /// The endpoint reads the catalog and changes nothing (D84), thus the
    /// schema has no `Mutation` type.
    @Test func theSchemaHasNoMutation() async throws {
        let fixture = try await AgentsGraphFixture.make(layers: [])

        let schema = try buildSchema(source: fixture.graph.schema)

        #expect(schema.mutationType == nil)
    }

    // MARK: - Queries

    /// `agents` gives each agent of the catalog, sorted by id.
    @Test func agentsGivesEachAgentOfTheCatalog() async throws {
        let layer = try Self.makeLayer(ids: [Self.reviewerID, AgentFolderFixture.helperID])
        defer { try? layer.delete() }
        let fixture = try await AgentsGraphFixture.make(layers: [layer.layer])

        let reply = try await fixture.run(AgentsGraphFixture.agentsQuery)
        let ids = try reply.objects("agents").map { $0["id"] as? String }

        #expect(reply.codes.isEmpty)
        #expect(ids == [AgentFolderFixture.helperID, Self.reviewerID])
    }

    /// `agent(id:)` gives the keys of one agent, its visibility, and its
    /// layer. A local agent has no marketplace.
    @Test func agentGivesTheFieldsOfOneAgent() async throws {
        let layer = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: AgentFolderFixture.helperID): Self.agentWithEachKey
        ])
        defer { try? layer.delete() }
        let fixture = try await AgentsGraphFixture.make(layers: [layer.layer])

        let agent = try await fixture.agent(AgentFolderFixture.helperID).object("agent")
        let agentLayer = try #require(agent["layer"] as? [String: Any])

        #expect(agent["id"] as? String == AgentFolderFixture.helperID)
        #expect(agent["description"] as? String == AgentFolderFixture.description)
        #expect(agent["model"] as? String == Self.model)
        #expect(agent["color"] as? String == Self.color)
        #expect(agent["background"] as? Bool == true)
        #expect(agent["isModelVisible"] as? Bool == false)
        #expect(agent["isUserInvocable"] as? Bool == false)
        #expect(agent["isDefault"] as? Bool == false)
        #expect(agent["marketplace"] is NSNull)
        #expect(agentLayer["name"] as? String == Self.projectLayerName)
        #expect(agentLayer["root"] as? String == layer.root.path)
    }

    /// An id that no agent has gives `null`, and no error.
    @Test func anUnknownIDGivesNull() async throws {
        let layer = try Self.makeLayer(ids: [AgentFolderFixture.helperID])
        defer { try? layer.delete() }
        let fixture = try await AgentsGraphFixture.make(layers: [layer.layer])

        let reply = try await fixture.agent(Self.unknownID)

        #expect(reply.codes.isEmpty)
        #expect(reply.isNull("agent"))
    }

    /// The `id` argument is an `ID`, thus it also takes an Int: an Int
    /// literal finds the agent whose id is its decimal text, and the output
    /// id is that text as a String.
    @Test func anIntIDFindsTheAgentOfItsDecimalText() async throws {
        let layer = try Self.makeLayer(ids: [Self.decimalID])
        defer { try? layer.delete() }
        let fixture = try await AgentsGraphFixture.make(layers: [layer.layer])

        let reply = try await fixture.run("{ agent(id: \(Self.decimalID)) { id } }")

        #expect(reply.codes.isEmpty)
        #expect(try reply.object("agent")["id"] as? String == Self.decimalID)
    }

    /// The root `AGENT.md` of a local layer is the default agent: its id is
    /// `default`, and `isDefault` is `true`.
    @Test func theRootDocumentIsTheDefaultAgent() async throws {
        let layer = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName)
        ])
        defer { try? layer.delete() }
        let fixture = try await AgentsGraphFixture.make(layers: [layer.userLayer])

        let agent = try await fixture.agent(AgentFolderFixture.defaultAgentID).object("agent")
        let agentLayer = try #require(agent["layer"] as? [String: Any])

        #expect(agent["id"] as? String == AgentFolderFixture.defaultAgentID)
        #expect(agent["isDefault"] as? Bool == true)
        #expect(agentLayer["name"] as? String == Self.userLayerName)
    }

    /// An agent of a marketplace layer gives the marketplace that holds it:
    /// its id and the commit of its snapshot.
    @Test func aMarketplaceAgentGivesItsMarketplace() async throws {
        let provider = try await FixtureMarketplaceProvider.make()
        defer { try? provider.delete() }
        let fixture = try await AgentsGraphFixture.make(
            registry: AgentRegistry(marketplaces: provider, stack: DotfolderStack(layers: [])))
        let id = try #require(FixtureMarketplaceProvider.agentIDs.first)

        let agent = try await fixture.agent(id).object("agent")
        let marketplace = try #require(agent["marketplace"] as? [String: Any])
        let agentLayer = try #require(agent["layer"] as? [String: Any])

        #expect(marketplace["id"] as? String == FixtureMarketplaceProvider.marketplaceID)
        #expect(marketplace["sha"] as? String == provider.sha)
        #expect(agentLayer["name"] as? String == Self.marketplaceLayerName)
    }

    /// Before the first load of the registry, the catalog is empty because
    /// the registry read no file. The endpoint refuses the query with
    /// `CATALOG_NOT_LOADED`, and does not give an empty list.
    @Test func aQueryBeforeTheFirstLoadIsRefused() async throws {
        let layer = try Self.makeLayer(ids: [AgentFolderFixture.helperID])
        defer { try? layer.delete() }
        let graph = try AgentsGraph(registry: AgentRegistry(layers: [layer.layer]))

        let reply = try await AgentsGraphFixture.run(AgentsGraphFixture.agentsQuery, on: graph)

        #expect(reply.codes == [Self.catalogNotLoadedCode])
    }

    // MARK: - Aliases

    /// `listAgents` names the `agents` field, and the response tells the
    /// rewrite.
    @Test func listAgentsIsAnAliasOfAgents() async throws {
        let layer = try Self.makeLayer(ids: [AgentFolderFixture.helperID])
        defer { try? layer.delete() }
        let fixture = try await AgentsGraphFixture.make(layers: [layer.layer])

        let reply = try await fixture.run("{ listAgents { id } }")

        #expect(reply.codes.isEmpty)
        #expect(try reply.objects("listAgents").map { $0["id"] as? String } == [AgentFolderFixture.helperID])
        #expect(reply.rewrites.contains { $0.from == "listAgents" && $0.to == "agents" })
    }

    /// `getAgent` and `findAgent` name the `agent` field, and `agentName`
    /// names its `id` argument.
    @Test(arguments: ["getAgent", "findAgent"])
    func aliasNamesTheAgentField(alias: String) async throws {
        let layer = try Self.makeLayer(ids: [AgentFolderFixture.helperID])
        defer { try? layer.delete() }
        let fixture = try await AgentsGraphFixture.make(layers: [layer.layer])

        let reply = try await fixture.run("{ \(alias)(agentName: \"\(AgentFolderFixture.helperID)\") { id } }")

        #expect(reply.codes.isEmpty)
        #expect(try reply.object(alias)["id"] as? String == AgentFolderFixture.helperID)
    }

    // MARK: - One port

    /// `list agents` of the `agents` tool and the endpoint read the catalog
    /// of one registry: after a reload, both give the new agent.
    @Test func listAgentsAndTheEndpointReadOneRegistry() async throws {
        let layer = try Self.makeLayer(ids: [AgentFolderFixture.helperID])
        defer { try? layer.delete() }
        let registry = AgentRegistry(layers: [layer.layer])
        let harness = try await AgentsToolHarness.make(registry: registry)
        defer { try? harness.delete() }
        let graph = try AgentsGraph(registry: registry)
        try layer.write(
            AgentFolderFixture.agentText(name: Self.reviewerID), at: AgentFolderFixture.documentPath(of: Self.reviewerID))

        try await registry.reload()
        let listing = try await harness.call(Self.listOperation)
        let reply = try await AgentsGraphFixture.run("{ agents { id } }", on: graph)
        let ids = try reply.objects("agents").map { $0["id"] as? String }

        #expect(listing.contains(Self.reviewerID))
        #expect(ids == [AgentFolderFixture.helperID, Self.reviewerID])
    }

    // MARK: - Helpers

    /// Makes a layer with one valid agent for each id.
    ///
    /// - Parameter ids: The ids of the agents.
    /// - Returns: The layer. The test deletes it.
    /// - Throws: The error of the file system.
    static func makeLayer(ids: [String]) throws -> TemporaryLayer {
        try TemporaryLayer.make(holding: Dictionary(uniqueKeysWithValues: ids.map { id in
            (AgentFolderFixture.documentPath(of: id), AgentFolderFixture.agentText(name: id))
        }))
    }
}
