/// One generation of the agent catalog: every agent that loaded, and every
/// diagnostic of the load.
///
/// A catalog is a value. `AgentRegistry.catalog()` gives the cached value,
/// and `AgentRegistry.load()` or `AgentRegistry.reload()` swaps in a new
/// one. A catalog that a caller holds does not change.
public struct AgentCatalog: Sendable {
    /// The fixed id of the default agent: the root `AGENT.md` of an
    /// agent-folder source, or `agents/default/AGENT.md` of a layer.
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
    /// `AGENT.md` of an agent-folder source replaces the built-in
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
    init(definitions: [AgentDefinition], diagnostics: [AgentDiagnostic]) {
        self.definitions = definitions.sorted { $0.id < $1.id }
        self.diagnostics = diagnostics
        self.definitionsByID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
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
