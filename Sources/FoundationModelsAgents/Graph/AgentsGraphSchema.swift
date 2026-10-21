import FoundationModelsExtras
import Graphiti
import GraphQL

// The GraphQL schema of the `agents` endpoint (AG-8): the context, the
// resolver, and the Graphiti API over one `AgentRegistry`. The types that the
// resolvers give are in `AgentsGraphTypes.swift`.

// MARK: - Resolver and context

/// The context of one call of the `agents` endpoint: the cursor and the
/// catalog that each field of the call reads.
///
/// The call reads the cursor of the change log first, then the catalog. The
/// change log takes the change of a build only after the build swapped its
/// catalog in, thus each change up to the cursor is in the catalog: a client
/// that reads `agents` and `cursor`, then subscribes to `changes(after:)`
/// with that cursor, misses no change (EXTRAS-9 rule 9). A change can come
/// one time more, never one time less.
struct AgentsGraphContext: GraphQLRunContext {
    /// The warnings of the call.
    let warnings = ResponseWarnings()

    /// The cursor of the newest change when the call started.
    let cursor: String

    /// The catalog of the call, or `nil` before the first load of the
    /// registry.
    private let catalog: AgentCatalog?

    /// Reads the cursor, then the catalog, of the current build of a
    /// registry.
    ///
    /// - Parameter build: The current build of the registry.
    init(reading build: AgentRegistry.CurrentBuild) async {
        cursor = await build.changeLog.cursor
        catalog = build.loadedCatalog()
    }

    /// Gives the catalog of the call.
    ///
    /// - Returns: The catalog. The call does no I/O.
    /// - Throws: ``AgentsGraphError/catalogNotLoaded`` before the first load
    ///   of the registry: its empty catalog does not tell that the folder has
    ///   no agent.
    func loadedCatalog() throws -> AgentCatalog {
        guard let catalog else {
            throw AgentsGraphError.catalogNotLoaded
        }
        return catalog
    }
}

/// The root resolver of the `agents` endpoint over the catalog and the
/// change log of one registry.
///
/// The registry is the port of the catalog (EXTRAS-9 rule 1): the
/// `list agents` operation of the `agents` tool reads the same `catalog()`.
/// Each query field reads the catalog of its call, ``AgentsGraphContext``,
/// thus each field of one call reads one build. The resolver holds the
/// change log of the registry, and keeps no reference to the registry.
struct AgentsGraphResolver: Sendable {
    /// The change log of the registry of the catalog of the session folder.
    let changeLog: ChangeLog<ChangedIDs>

    /// Resolves `Query.cursor`.
    ///
    /// - Parameter context: The context of the call.
    /// - Returns: The cursor of the newest change of the catalog that the
    ///   call reads.
    func cursor(context: AgentsGraphContext, arguments _: NoArguments) -> String {
        context.cursor
    }

    /// Resolves the source stream of `Subscription.changes`.
    ///
    /// - Parameter arguments: The cursor to resume after.
    /// - Returns: The changes after the cursor, or only the changes after the
    ///   start of the subscription when there is no cursor. The stream ends
    ///   with `RESYNC_REQUIRED` when the log cannot resume after the cursor.
    func changes(
        context _: AgentsGraphContext, arguments: AgentsGraphChangesArguments
    ) async -> ChangeLog<ChangedIDs>.Changes {
        await changeLog.changes(after: arguments.after)
    }

    /// Resolves `Query.agents`.
    ///
    /// - Parameter context: The context of the call.
    /// - Returns: Each agent of the catalog, sorted by id.
    /// - Throws: ``AgentsGraphError/catalogNotLoaded`` before the first load
    ///   of the registry.
    func agents(context: AgentsGraphContext, arguments _: NoArguments) throws -> [AgentsGraphAgent] {
        let catalog = try context.loadedCatalog()
        return catalog.definitions.map { definition in AgentsGraphAgent(definition, in: catalog) }
    }

    /// Resolves `Query.agent`.
    ///
    /// The id is the id that `start agent` accepts: the canonical id of the
    /// agent, ``AgentDefinition/id``.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The id of the agent.
    /// - Returns: The agent, or `nil` when no agent of the catalog has the id.
    /// - Throws: ``AgentsGraphError/catalogNotLoaded`` before the first load
    ///   of the registry.
    func agent(context: AgentsGraphContext, arguments: AgentsGraphAgentArguments) throws -> AgentsGraphAgent? {
        let catalog = try context.loadedCatalog()
        return catalog.definition(named: arguments.id.text).map { definition in
            AgentsGraphAgent(definition, in: catalog)
        }
    }

    /// Resolves `Query.diagnostics`.
    ///
    /// - Parameter context: The context of the call.
    /// - Returns: Each diagnostic of the catalog, in the order of the catalog:
    ///   also each diagnostic of a file that gave no agent.
    /// - Throws: ``AgentsGraphError/catalogNotLoaded`` before the first load
    ///   of the registry.
    func diagnostics(context: AgentsGraphContext, arguments _: NoArguments) throws -> [AgentsGraphDiagnostic] {
        try context.loadedCatalog().diagnostics.map(AgentsGraphDiagnostic.init)
    }
}

// MARK: - The API

/// The Graphiti engine of the `agents` endpoint.
struct AgentsGraphAPI: API {
    /// The type of a component of the schema.
    typealias SchemaType = TypeComponent<AgentsGraphResolver, AgentsGraphContext>

    /// The type of a root field of the schema: a query or a subscription.
    typealias QueryField = FieldComponent<AgentsGraphResolver, AgentsGraphContext>

    /// The text of the description of a `diagnostics` field of an agent.
    private static let diagnosticsDescription =
        "Each finding of the load of the catalog that names this agent, for example a missing description."

    /// The root resolver.
    let resolver: AgentsGraphResolver

    /// The schema.
    let schema: Schema<AgentsGraphResolver, AgentsGraphContext>

    /// Builds the schema over the change log of a registry.
    ///
    /// - Parameter changeLog: The change log of the registry of the catalog.
    /// - Throws: An error of the schema builder.
    init(changeLog: ChangeLog<ChangedIDs>) throws {
        resolver = AgentsGraphResolver(changeLog: changeLog)
        schema = try SchemaBuilder(AgentsGraphResolver.self, AgentsGraphContext.self)
            .addToolkitScalars()
            .addToolkitIDScalar()
            .add {
                Self.layerNameEnum()
                Self.severityEnum()
                Self.layerType()
                Self.marketplaceType()
                Self.agentType()
                Self.diagnosticType()
                Self.changeType()
            }
            .addQuery {
                Self.cursorField()
                Self.agentsField()
                Self.agentField()
                Self.diagnosticsField()
            }
            .addSubscription {
                Self.changesField()
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

    /// The `AgentChange` type: the shared change shape of the toolkit,
    /// ``IDChange``, under the name that EXTRAS-9 rule 9 gives it for the
    /// noun `Agent`.
    ///
    /// - Returns: The type.
    private static func changeType() -> SchemaType {
        Type(IDChange.self, as: "AgentChange") {
            Field("cursor", at: \.cursor).description("The cursor that resumes after this change.")
            Field("at", at: \.at).description("The time of the reload that made the change.")
            Field("added", at: \.added)
                .description("The ids of the agents that the reload added. Query agent(id:) for each.")
            Field("changed", at: \.changed)
                .description(
                    "The ids of the agents whose file or diagnostics the reload changed. Query agent(id:) for each.")
            Field("removed", at: \.removed)
                .description("The ids of the agents that the reload removed. A removed agent needs no query.")
        }
        .description("One reload of the catalog of the session folder that added, changed or removed an agent.")
    }

    // MARK: Query fields

    /// The `Query.cursor` field.
    ///
    /// - Returns: The field.
    private static func cursorField() -> QueryField {
        Field("cursor", at: AgentsGraphResolver.cursor)
            .description(
                "The cursor of the newest change of the catalog that this call reads, for changes(after:).")
    }

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

    // MARK: Subscription fields

    /// The `Subscription.changes(after:)` field: one ``IDChange`` for each
    /// entry of the change log.
    ///
    /// - Returns: The field.
    private static func changesField() -> QueryField {
        SubscriptionField(
            "changes",
            at: { (entry: ChangeLogEntry<ChangedIDs>) in
                { (_: AgentsGraphContext, _: AgentsGraphChangesArguments) async throws -> IDChange in
                    IDChange(entry)
                }
            },
            atSub: AgentsGraphResolver.changes
        ) {
            Argument("after", at: \.after)
                .description("The cursor to resume after, from cursor or a change. Omit it for the new changes only.")
        }
        .description(
            "One change for each reload that adds, changes or removes an agent. "
                + "A cursor that cannot resume gives RESYNC_REQUIRED.")
    }
}
