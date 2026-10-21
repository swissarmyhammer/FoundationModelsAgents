import FoundationModelsExtras
import GraphQL

/// The `agents` GraphQL endpoint (AG-8, EXTRAS-9): the agent catalog of the
/// session folder for the clients of the agent, over one ``AgentRegistry``.
///
/// The endpoint has the scope of the session folder: the host keeps one
/// registry for each session folder, whose project layer is that folder
/// (AG-10). Thus the catalog of a call is the catalog that the session of the
/// call sees. The registry is the one port of the catalog (EXTRAS-9 rule 1):
/// the `list agents` operation of the `agents` tool reads the same
/// `catalog()` (``AgentsToolContext``).
///
/// - `Query.agents` gives each agent of the catalog, sorted by id.
/// - `Query.agent(id:)` gives one agent, or `null` for an id that no agent
///   has. The id is the id that `start agent` takes.
/// - `Query.diagnostics` gives each finding of the load, each with an
///   `UPPER_SNAKE` code (``AgentDiagnostic/Code``). `Agent.diagnostics` gives
///   the findings of one agent.
///
/// The endpoint changes nothing: it has no `Mutation` type (D84). Before the
/// first `load()` of the registry, each query field gives
/// ``AgentsGraphError/catalogNotLoaded``. The `changes(after:)` subscription
/// and the root `cursor` of EXTRAS-9 rule 9 are not here yet (^20mv6d3).
///
/// The endpoint is a reference type: the registry makes one endpoint, and
/// each ``AgentsTool`` over the registry gives that same instance in its
/// `graphQLEndpoints` (EXTRAS-9 rule 1). A host finds it with
/// `tool as? any GraphQLEndpointTool`, or with no tool through
/// ``AgentRegistry/agentsGraph()``. The endpoint reads the catalog of the
/// registry, and it does not keep the registry.
public final class AgentsGraph: GraphQLEndpoint {
    /// The name of the endpoint.
    public static let endpointName = "agents"

    /// The other names that a call can write for the names of the schema
    /// (D86).
    ///
    /// The standard query verb `find` gives the plural field, thus
    /// `findAgent` would give `agents`. The rules leave `find` out of the
    /// query verbs, and the alias tables give `findAgent` to `agent` and
    /// `findAgents` to `agents`.
    static let rules = GraphQLNameRules(
        aliases: GraphQLAliasTable(
            inEachInput: ["id": ["name", "agentName"]],
            byType: [
                "Query": [
                    "agents": ["listAgents", "allAgents", "findAgents"],
                    "agent": ["getAgent", "findAgent"],
                ]
            ],
            byField: ["Query.agent": ["id": ["name", "agentName"]]]),
        queryVerbs: GraphQLNameRules.standardQueryVerbs.filter { verb, _ in verb != "find" }
    )

    /// The name of the endpoint.
    public let name = endpointName

    /// The version of the schema.
    public let version = "1"

    /// The scope of the endpoint: the session folder.
    public let scope = GraphQLEndpointScope.sessionFolder

    /// The Graphiti engine of the endpoint.
    private let api: AgentsGraphAPI

    /// Makes an endpoint over a registry.
    ///
    /// The endpoint reads the same catalog as the endpoint that the `agents`
    /// tool gives, but it is a new instance. A host reads the one endpoint
    /// of the registry, ``AgentRegistry/agentsGraph()``, instead.
    ///
    /// - Parameter registry: The registry of the catalog of the session
    ///   folder. The host loads it; the endpoint never reads a file.
    /// - Throws: An error of the schema builder.
    public convenience init(registry: AgentRegistry) throws {
        try self.init(build: registry.currentBuild)
    }

    /// Makes an endpoint over the current build of a registry.
    ///
    /// ``AgentsGraphPort`` uses this init, thus the endpoint of the registry
    /// keeps no reference to the registry.
    ///
    /// - Parameter build: The current build of the registry of the catalog.
    /// - Throws: An error of the schema builder.
    init(build: AgentRegistry.CurrentBuild) throws {
        api = try AgentsGraphAPI(build: build)
    }

    /// The schema of the endpoint in SDL.
    public var schema: String {
        api.sdl
    }

    /// Runs one GraphQL document.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil`.
    ///   - viewer: The client that makes the call, or `nil` for the agent.
    ///     The host checks the folder of the call, thus each viewer sees the
    ///     same catalog.
    /// - Returns: The GraphQL response as JSON text.
    /// - Throws: A fault that is not a GraphQL error.
    public func execute(
        query: String, variables: [String: Map], operationName: String?, viewer _: GraphQLViewer?
    ) async throws -> String {
        try await api.respond(
            to: query, variables: variables, operationName: operationName, rules: Self.rules,
            formattedWith: .sortedKeys, context: AgentsGraphContext())
    }

    /// Starts one GraphQL subscription. The schema has no subscription yet
    /// (^20mv6d3), thus a subscription document gives one response with the
    /// errors of the toolkit.
    ///
    /// - Parameters:
    ///   - query: The subscription document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil`.
    ///   - viewer: The client that makes the call, or `nil` for the agent.
    /// - Returns: The GraphQL response of each event as JSON text.
    /// - Throws: A fault that is not a GraphQL error.
    public func subscribe(
        query: String, variables: [String: Map], operationName: String?, viewer _: GraphQLViewer?
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await api.subscribe(
            to: query, variables: variables, operationName: operationName, rules: Self.rules,
            formattedWith: .sortedKeys, context: AgentsGraphContext())
    }
}
