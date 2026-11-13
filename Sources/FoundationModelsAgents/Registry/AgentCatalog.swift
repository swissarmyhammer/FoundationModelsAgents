/// One generation of the agent catalog: every agent that loaded, and every
/// diagnostic of the load.
///
/// A catalog is a value. `AgentRegistry.catalog()` gives the cached value,
/// and `AgentRegistry.load()` or `AgentRegistry.reload()` swaps in a new
/// one. A catalog that a caller holds does not change.
public struct AgentCatalog: Sendable {
    /// The fixed id of the default agent: the root `AGENT.md` of a local
    /// layer, or `agents/default/AGENT.md` of a layer.
    ///
    /// The id does not come from the name of a folder, thus the precedence
    /// of the layers applies to the default agent as to each other agent.
    public static let defaultAgentID = "default"

    /// Each agent that loaded, sorted by id.
    public let definitions: [AgentDefinition]

    /// Each diagnostic of the load. First the diagnostics of the agent
    /// folders, in the id order of the folders. The diagnostics of one folder
    /// keep the order of the load. Then one warning for each agent file of the
    /// old format, `agents/<name>.md`, sorted by file name, then by layer.
    public let diagnostics: [AgentDiagnostic]

    /// Each agent that loaded, by id.
    private let definitionsByID: [String: AgentDefinition]

    /// The unresolved conflict versions of the file of each agent, by id.
    /// An agent with no conflict version has no entry.
    private let conflictsByID: [String: [AgentConflictVersion]]

    /// The listing of each agent that loaded, sorted by id.
    public var listing: [AgentListing] {
        definitions.map(\.listing)
    }

    /// Each agent that the model can see and start, sorted by id.
    public var modelVisible: [AgentDefinition] {
        definitions.filter(\.isModelVisible)
    }

    /// The default agent: the agent with the id ``defaultAgentID``, or `nil`
    /// when no layer gives it.
    ///
    /// A host starts its root session from this agent when it is present,
    /// and uses its own instructions when it is `nil`. Thus the root
    /// `AGENT.md` of the root settings folder replaces the built-in
    /// instructions of the host.
    public var defaultAgent: AgentDefinition? {
        definition(named: Self.defaultAgentID)
    }

    /// Each agent that the user can start as a slash command, sorted by id.
    public var userInvocable: [AgentDefinition] {
        definitions.filter(\.isUserInvocable)
    }

    /// Makes a catalog.
    ///
    /// - Parameters:
    ///   - definitions: Each agent that loaded. Each id occurs one time.
    ///   - diagnostics: Each diagnostic of the load, in order.
    ///   - conflicts: The unresolved conflict versions of the file of each
    ///     agent, by id. The default is no conflict versions.
    init(
        definitions: [AgentDefinition], diagnostics: [AgentDiagnostic],
        conflicts: [String: [AgentConflictVersion]] = [:]
    ) {
        self.definitions = definitions.sorted { $0.id < $1.id }
        self.diagnostics = diagnostics
        self.definitionsByID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        self.conflictsByID = conflicts.filter { !$0.value.isEmpty }
    }

    /// Gives the unresolved conflict versions of the file of one agent.
    ///
    /// - Parameter id: The id of the agent.
    /// - Returns: The versions in the order of the source, or an empty list
    ///   when the file has no conflict version or no agent has the id.
    public func conflicts(of id: String) -> [AgentConflictVersion] {
        conflictsByID[id] ?? []
    }

    /// Gives this catalog with the diagnostics `diagnostics` and the same
    /// agents and conflict versions.
    ///
    /// - Parameter diagnostics: The diagnostics of the new catalog.
    /// - Returns: The catalog.
    func replacingDiagnostics(with diagnostics: [AgentDiagnostic]) -> AgentCatalog {
        AgentCatalog(definitions: definitions, diagnostics: diagnostics, conflicts: conflictsByID)
    }

    /// Gives this catalog with the conflict versions of the file of each
    /// agent of a local layer. The call reads the versions from `source`.
    /// A marketplace agent has no conflict version: its folder is a cache.
    ///
    /// - Parameter source: The source of the conflict versions.
    /// - Returns: The catalog.
    func readingConflicts(from source: any AgentConflictVersionSource) -> AgentCatalog {
        let conflicts = definitions.filter { $0.marketplace == nil }.map { definition in
            (definition.id, source.conflictVersions(of: definition.url))
        }
        return AgentCatalog(
            definitions: definitions, diagnostics: diagnostics,
            conflicts: Dictionary(uniqueKeysWithValues: conflicts))
    }

    /// Finds the agent with the id `id`.
    ///
    /// - Parameter id: The id of the agent: the name of its folder.
    /// - Returns: The agent, or `nil` when no agent of this catalog has the
    ///   id.
    public func definition(named id: String) -> AgentDefinition? {
        definitionsByID[id]
    }
}
