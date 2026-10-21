import FoundationModelsExtras
import FoundationModelsRouter

/// The change between two catalogs of one registry, by agent id: the event
/// that the change log of the `agents` endpoint takes for one reload
/// (EXTRAS-9 rule 9).
///
/// An id that only the later catalog has is added, and an id that only the
/// earlier catalog has is removed. An id of both catalogs is changed when
/// its content differs: the `Agent` object that the endpoint gives (the
/// keys, the visibility, the layer, the marketplace and the diagnostics),
/// and the file (its path, its body, and each key that the `Agent` type does
/// not give). Thus a client that queries `agent(id:)` again for each added
/// and changed id reads each change.
///
/// A diagnostic that names an id with no agent in either catalog, for
/// example an agent that does not load, makes that id changed when the
/// diagnostics of the id change.
enum AgentCatalogChanges {
    /// Gives the change between two catalogs.
    ///
    /// - Parameters:
    ///   - previous: The catalog before the reload.
    ///   - next: The catalog after the reload.
    /// - Returns: The ids that `next` adds, changes and removes, each list
    ///   sorted, or `nil` when no id changed.
    static func change(from previous: AgentCatalog, to next: AgentCatalog) -> ChangedIDs? {
        let before = contents(of: previous)
        let after = contents(of: next)
        let previousIDs = Set(previous.definitions.map(\.id))
        let nextIDs = Set(next.definitions.map(\.id))
        let added = nextIDs.subtracting(previousIDs)
        let removed = previousIDs.subtracting(nextIDs)
        let changed = Set(before.keys).union(after.keys).subtracting(added).subtracting(removed)
            .filter { id in before[id] != after[id] }
        guard !(added.isEmpty && changed.isEmpty && removed.isEmpty) else {
            return nil
        }
        return ChangedIDs(added: added.sorted(), changed: changed.sorted(), removed: removed.sorted())
    }

    /// Gives the content of each id of a catalog: each agent, and each id
    /// that a diagnostic names.
    ///
    /// - Parameter catalog: The catalog.
    /// - Returns: The content of each id, keyed by id.
    private static func contents(of catalog: AgentCatalog) -> [String: AgentContent] {
        let ids = Set(catalog.definitions.map(\.id)).union(catalog.diagnostics.compactMap(\.agent))
        return Dictionary(uniqueKeysWithValues: ids.map { id in (id, AgentContent(id: id, in: catalog)) })
    }
}

/// What one catalog holds for one agent id, in the form that the change
/// feed compares.
private struct AgentContent: Equatable {
    /// The `Agent` object that the endpoint gives, or `nil` when the catalog
    /// has no agent of the id.
    let agent: AgentsGraphAgent?

    /// The file of the agent, or `nil` when the catalog has no agent of the
    /// id.
    let file: AgentFile?

    /// Each diagnostic of the catalog that names the id.
    let diagnostics: [AgentsGraphDiagnostic]

    /// Reads the content of one id.
    ///
    /// - Parameters:
    ///   - id: The id.
    ///   - catalog: The catalog.
    init(id: String, in catalog: AgentCatalog) {
        let definition = catalog.definition(named: id)
        agent = definition.map { definition in AgentsGraphAgent(definition, in: catalog) }
        file = definition.map(AgentFile.init)
        diagnostics = AgentsGraphDiagnostic.naming(id, in: catalog)
    }

    /// Whether two contents of one id are the same: the same `Agent` object,
    /// the same file, and the same diagnostics.
    ///
    /// - Parameters:
    ///   - lhs: The content in one catalog.
    ///   - rhs: The content in the other catalog.
    /// - Returns: `true` when no part differs.
    static func == (lhs: AgentContent, rhs: AgentContent) -> Bool {
        lhs.agent == rhs.agent && lhs.file == rhs.file && lhs.diagnostics == rhs.diagnostics
    }
}

/// The parts of an agent file that the `Agent` type does not give: the path,
/// the body, and the keys that only a run reads.
private struct AgentFile: Equatable {
    /// The path of the file.
    let path: String

    /// Where the document sits in its layer.
    let kind: AgentDocumentKind

    /// The raw body of the file.
    let body: String

    /// The fold prompt of the agent.
    let compactionPrompt: CompactionPrompt?

    /// The turn limit of the agent.
    let maxTurns: Int?

    /// The `tools` entries.
    let tools: [String]?

    /// The `disallowedTools` entries.
    let disallowedTools: [String]

    /// The skills that a run preloads.
    let skills: [String]

    /// The keys that the package does not know, with their values.
    let unknownFields: [String: YAMLValue]

    /// Reads the file of one agent.
    ///
    /// - Parameter definition: The agent.
    init(_ definition: AgentDefinition) {
        path = definition.url.path
        kind = definition.kind
        body = definition.body
        compactionPrompt = definition.compactionPrompt
        maxTurns = definition.maxTurns
        tools = definition.tools
        disallowedTools = definition.disallowedTools
        skills = definition.skills
        unknownFields = definition.unknownFields
    }

    /// Whether two files of one id are the same: each part that the file
    /// keeps is equal.
    ///
    /// - Parameters:
    ///   - lhs: The file in one catalog.
    ///   - rhs: The file in the other catalog.
    /// - Returns: `true` when no part differs.
    static func == (lhs: AgentFile, rhs: AgentFile) -> Bool {
        lhs.path == rhs.path && lhs.kind == rhs.kind && lhs.body == rhs.body
            && lhs.compactionPrompt == rhs.compactionPrompt && lhs.maxTurns == rhs.maxTurns
            && lhs.tools == rhs.tools && lhs.disallowedTools == rhs.disallowedTools && lhs.skills == rhs.skills
            && lhs.unknownFields == rhs.unknownFields
    }
}
