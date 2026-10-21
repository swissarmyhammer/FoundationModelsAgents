import FoundationModelsExtras
import Graphiti
import GraphQL

// The GraphQL schema of the `agents` endpoint (AG-8): the context, the
// resolver, and the Graphiti API over one `AgentRegistry`. The types that the
// resolvers give are in `AgentsGraphTypes.swift`.

// MARK: - Resolver and context

/// The context of one call of the `agents` endpoint.
struct AgentsGraphContext: GraphQLRunContext {
    /// The warnings of the call.
    let warnings = ResponseWarnings()
}

/// The root resolver of the `agents` endpoint over the catalog of one
/// registry.
///
/// The registry is the port of the catalog (EXTRAS-9 rule 1): the
/// `list agents` operation of the `agents` tool reads the same `catalog()`.
/// Each resolver reads the catalog one time, thus one field gives the agents
/// of one build.
struct AgentsGraphResolver: Sendable {
    /// The registry of the catalog of the session folder.
    let registry: AgentRegistry

    /// Resolves `Query.agents`.
    ///
    /// - Returns: Each agent of the catalog, sorted by id.
    /// - Throws: ``AgentsGraphError/catalogNotLoaded`` before the first load
    ///   of the registry.
    func agents(context _: AgentsGraphContext, arguments _: NoArguments) throws -> [AgentsGraphAgent] {
        let catalog = try loadedCatalog()
        return catalog.definitions.map { definition in AgentsGraphAgent(definition, in: catalog) }
    }

    /// Resolves `Query.agent`.
    ///
    /// The id is the id that `start agent` accepts: the canonical id of the
    /// agent, ``AgentDefinition/id``.
    ///
    /// - Parameter arguments: The id of the agent.
    /// - Returns: The agent, or `nil` when no agent of the catalog has the id.
    /// - Throws: ``AgentsGraphError/catalogNotLoaded`` before the first load
    ///   of the registry.
    func agent(context _: AgentsGraphContext, arguments: AgentsGraphAgentArguments) throws -> AgentsGraphAgent? {
        let catalog = try loadedCatalog()
        return catalog.definition(named: arguments.id).map { definition in
            AgentsGraphAgent(definition, in: catalog)
        }
    }

    /// Resolves `Query.diagnostics`.
    ///
    /// - Returns: Each diagnostic of the catalog, in the order of the catalog:
    ///   also each diagnostic of a file that gave no agent.
    /// - Throws: ``AgentsGraphError/catalogNotLoaded`` before the first load
    ///   of the registry.
    func diagnostics(context _: AgentsGraphContext, arguments _: NoArguments) throws -> [AgentsGraphDiagnostic] {
        try loadedCatalog().diagnostics.map(AgentsGraphDiagnostic.init)
    }

    /// Gives the catalog of the last build of the registry.
    ///
    /// - Returns: The catalog. The call does no I/O.
    /// - Throws: ``AgentsGraphError/catalogNotLoaded`` before the first load
    ///   of the registry: its empty catalog does not tell that the folder has
    ///   no agent.
    private func loadedCatalog() throws -> AgentCatalog {
        guard registry.isLoaded else {
            throw AgentsGraphError.catalogNotLoaded
        }
        return registry.catalog()
    }
}

// MARK: - The API

/// The Graphiti engine of the `agents` endpoint.
struct AgentsGraphAPI: API {
    /// The type of a component of the schema.
    typealias SchemaType = TypeComponent<AgentsGraphResolver, AgentsGraphContext>

    /// The type of a root query field of the schema.
    typealias QueryField = FieldComponent<AgentsGraphResolver, AgentsGraphContext>

    /// The text of the description of a `diagnostics` field of an agent.
    private static let diagnosticsDescription =
        "Each finding of the load of the catalog that names this agent, for example a missing description."

    /// The root resolver.
    let resolver: AgentsGraphResolver

    /// The schema.
    let schema: Schema<AgentsGraphResolver, AgentsGraphContext>

    /// Builds the schema over a registry.
    ///
    /// - Parameter registry: The registry of the catalog.
    /// - Throws: An error of the schema builder.
    init(registry: AgentRegistry) throws {
        resolver = AgentsGraphResolver(registry: registry)
        schema = try SchemaBuilder(AgentsGraphResolver.self, AgentsGraphContext.self)
            .addToolkitScalars()
            .add {
                Self.layerNameEnum()
                Self.severityEnum()
                Self.layerType()
                Self.marketplaceType()
                Self.agentType()
                Self.diagnosticType()
            }
            .addQuery {
                Self.agentsField()
                Self.agentField()
                Self.diagnosticsField()
            }
            .build()
    }

    // MARK: Enums

    /// The `AgentLayerName` enum.
    ///
    /// - Returns: The enum.
    private static func layerNameEnum() -> SchemaType {
        Enum(AgentsGraphLayerName.self, as: "AgentLayerName") {
            Value(.defaults).description("The defaults folder of the host.")
            Value(.user).description("The user layer, for example the root settings folder of the host.")
            Value(.project).description("The folder of the session. It wins over each other layer.")
            Value(.marketplace).description("A cached marketplace. Each local layer wins over it.")
        }
        .description("The kind of the layer that gave an agent.")
    }

    /// The `AgentDiagnosticSeverity` enum.
    ///
    /// - Returns: The enum.
    private static func severityEnum() -> SchemaType {
        Enum(AgentsGraphSeverity.self, as: "AgentDiagnosticSeverity") {
            Value(.advisory).description("The agent loads with no change.")
            Value(.warning).description("The agent loads, possibly with a changed visibility.")
            Value(.skip).description("The agent does not load.")
        }
        .description("How serious a diagnostic is.")
    }

    // MARK: Object types

    /// The `AgentLayer` type.
    ///
    /// - Returns: The type.
    private static func layerType() -> SchemaType {
        Type(AgentsGraphLayer.self, as: "AgentLayer") {
            Field("name", at: \.name).description("The kind of the layer.")
            Field("root", at: \.root).description("The absolute path of the root folder of the layer.")
        }
        .description("The layer that gave an agent. The highest layer that holds an agent wins it.")
    }

    /// The `AgentMarketplace` type.
    ///
    /// - Returns: The type.
    private static func marketplaceType() -> SchemaType {
        Type(AgentsGraphMarketplace.self, as: "AgentMarketplace") {
            Field("id", at: \.id).description("The display id of the marketplace.")
            Field("sha", at: \.sha).description("The commit of the snapshot, or null before the first install.")
        }
        .description("The marketplace that gave an agent. The URL of its source is never given.")
    }

    /// The `Agent` type.
    ///
    /// - Returns: The type.
    private static func agentType() -> SchemaType {
        Type(AgentsGraphAgent.self, as: "Agent") {
            Field("id", at: \.id).description("The id of the agent: the name of its folder.")
            Field("description", at: \.description)
                .description("The description key: when to use the agent. Null when the key is absent.")
            Field("model", at: \.model).description("The model key, or null when the key is absent or empty.")
            Field("color", at: \.color).description("The color key, or null when the key is absent.")
            Field("background", at: \.background).description("The background key, or null when the key is absent.")
            Field("isModelVisible", at: \.isModelVisible)
                .description(
                    "True when the model can see and start the agent: it has a description, and "
                        + "disable-model-invocation is not true.")
            Field("isUserInvocable", at: \.isUserInvocable)
                .description("True when the agent is a slash command: user-invocable is not false.")
            Field("isDefault", at: \.isDefault)
                .description("True for the default agent, the root AGENT.md of a layer, with the id default.")
            Field("layer", at: \.layer).description("The layer that gave the agent.")
            Field("marketplace", at: \.marketplace)
                .description("The marketplace that gave the agent, or null for a local layer.")
            Field("diagnostics", at: \.diagnostics).description(diagnosticsDescription)
        }
        .description("One agent of the catalog of the session folder.")
    }

    /// The `AgentDiagnostic` type.
    ///
    /// - Returns: The type.
    private static func diagnosticType() -> SchemaType {
        Type(AgentsGraphDiagnostic.self, as: "AgentDiagnostic") {
            Field("code", at: \.code)
                .description(
                    "The code of the finding in UPPER_SNAKE, for example MISSING_DESCRIPTION, NOT_LOCAL, "
                        + "HIDDEN_COPY or DUPLICATE_DEFAULT. A client keys on the code, not on the message.")
            Field("severity", at: \.severity).description("How serious the finding is.")
            Field("agent", at: \.agent)
                .description("The id of the agent, or null when the folder name is not a valid id.")
            Field("path", at: \.path).description("The absolute path of the file that the finding is about.")
            Field("layerRoot", at: \.layerRoot)
                .description("The absolute path of the root folder of the layer of the file.")
            Field("message", at: \.message).description("The text of the finding, for a person.")
        }
        .description("One finding of the load of the catalog. A finding never stops the load of another file.")
    }

    // MARK: Query fields

    /// The `Query.agents` field.
    ///
    /// - Returns: The field.
    private static func agentsField() -> QueryField {
        Field("agents", at: AgentsGraphResolver.agents)
            .description("Each agent of the catalog of the session folder, sorted by id.")
    }

    /// The `Query.agent(id:)` field.
    ///
    /// - Returns: The field.
    private static func agentField() -> QueryField {
        Field("agent", at: AgentsGraphResolver.agent) {
            Argument("id", at: \.id).description("The id of the agent, as start agent takes it.")
        }
        .description("One agent of the catalog, or null when no agent has the id.")
    }

    /// The `Query.diagnostics` field.
    ///
    /// - Returns: The field.
    private static func diagnosticsField() -> QueryField {
        Field("diagnostics", at: AgentsGraphResolver.diagnostics)
            .description("Each finding of the load of the catalog, also of a file that gave no agent.")
    }
}
