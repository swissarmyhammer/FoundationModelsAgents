/// One generation of the agent catalog (plan.md §4.1, §12): every agent that
/// loaded, and every diagnostic of the load.
///
/// A catalog is a value. `AgentRegistry.catalog()` gives the cached value,
/// and `AgentRegistry.load()` or `AgentRegistry.reload()` swaps in a new
/// one. A catalog that a caller holds does not change.
public struct AgentCatalog: Sendable {
    /// Each agent that loaded, sorted by id.
    public let definitions: [AgentDefinition]

    /// Each diagnostic of the load, in the id order of the files. The
    /// diagnostics of one file keep the order of the load.
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
    /// - Parameter id: The id of the agent: the file name with no `.md`.
    /// - Returns: The agent, or `nil` when no agent of this catalog has the
    ///   id.
    public func definition(named id: String) -> AgentDefinition? {
        definitionsByID[id]
    }
}
