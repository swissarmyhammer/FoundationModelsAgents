import FoundationModels
import FoundationModelsRouter
import FoundationModelsSkills

/// One agent of the search index of `find agents`: the id and the
/// description of a model-visible agent.
///
/// The search ranks this text and the selection model reads it. It holds no
/// body, thus a search never shows the system prompt of an agent.
struct AgentSearchEntry: SearchableMetadata {
    /// The id of the agent.
    let id: String

    /// The description of the agent.
    let description: String

    /// Makes the entry of `definition`, or `nil` when the model cannot see
    /// the agent. Thus an agent with no valid description, and an agent with
    /// `disable-model-invocation: true`, are never in the index.
    ///
    /// - Parameter definition: An agent of the catalog.
    init?(_ definition: AgentDefinition) {
        guard definition.isModelVisible, let description = definition.description else {
            return nil
        }
        id = definition.id
        self.description = description
    }

    /// Gives the text that the search ranks, embeds, and shows to the
    /// selection model: the id, then the description on the next line.
    ///
    /// - Returns: The text of the entry.
    func renderBlock() -> String {
        id + "\n" + description
    }

    /// Gives the entries of the model-visible agents of `catalog`.
    ///
    /// - Parameter catalog: A catalog of the registry.
    /// - Returns: One entry for each model-visible agent, in catalog order.
    static func entries(of catalog: AgentCatalog) -> [AgentSearchEntry] {
        catalog.definitions.compactMap(AgentSearchEntry.init)
    }
}

/// Gives the embedding model of a resolved profile to a search index.
///
/// The index embeds through `PooledEmbedding`. The embedding slot of the
/// profile, `LanguageModelProfile.embedding`, has the same `embed(texts:)`
/// call, but it does not conform to that protocol.
struct ProfileEmbedding: PooledEmbedding {
    /// The embedding model of the profile.
    let model: RoutedEmbedder

    /// Embeds each text with the embedding model of the profile.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: One vector for each text, in the order of `texts`.
    /// - Throws: The error of the embedding model.
    func embed(texts: [String]) async throws -> [[Float]] {
        try await model.embed(texts: texts)
    }
}

/// The search of `find agents` over the model-visible agents of one
/// registry.
///
/// The search uses the selection parts of FoundationModelsSkills, as
/// `SkillsTool.make(registry:model:)` assembles them for the `skills` tool:
///
/// - A `MetadataSearcher` ranks the descriptions with keywords and with the
///   cosine of the embedding (the retrieval tier).
/// - With a selection model, the searcher is in `.auto` mode with a
///   `SelectionConfig`: the selection model picks among the candidate
///   agents. A second searcher in `.retrieval` mode is the fallback. When the
///   answer of the selection model does not decode, the fallback ranks the
///   query, thus the call does not fail. The `search` span of the first
///   searcher records the error.
/// - With no selection model, the one searcher is in `.retrieval` mode.
///
/// The init subscribes to `AgentRegistry.onReload` first, then reads the
/// seed catalog. Thus no catalog of a reload between the two reads is lost.
/// One task follows the subscription, and gives each new catalog to the
/// searchers (`MetadataSearcher.update(items:)`). The task holds the stream
/// and the searchers, and never `self`. The `deinit` cancels it.
///
/// `final class ... Sendable`: each stored property is an immutable `let` of
/// a `Sendable` type, thus the class needs no lock.
final class AgentSearch: Sendable {
    /// The searcher that answers each search.
    private let searcher: MetadataSearcher<AgentSearchEntry>

    /// The searcher in `.retrieval` mode that ranks a query when the
    /// selection tier of ``searcher`` throws, or `nil` when ``searcher`` has
    /// no selection tier.
    private let retrievalFallback: MetadataSearcher<AgentSearchEntry>?

    /// The task that gives each catalog of `onReload` to the searchers.
    private let following: Task<Void, Never>

    /// Makes the search over the model-visible agents of `registry`, and
    /// starts to follow its reloads.
    ///
    /// The init embeds nothing. With an `embedder`, the first search embeds
    /// the seed catalog, and each reload embeds the entries that it changed.
    ///
    /// - Parameters:
    ///   - registry: The registry whose catalogs the search follows.
    ///   - selectionModel: The model that picks among the candidate agents,
    ///     or `nil` for the retrieval rank only.
    ///   - embedder: The embedder of the descriptions and of each query, or
    ///     `nil` for keywords only.
    init(
        registry: AgentRegistry, selectionModel: (any FoundationModels.LanguageModel)?,
        embedder: (any PooledEmbedding)?
    ) {
        let reloads = registry.onReload
        let index = MetadataIndex(items: AgentSearchEntry.entries(of: registry.catalog()))
        let searcher = MetadataSearcher(
            index: index, mode: selectionModel == nil ? .retrieval : .auto, embedder: embedder,
            selection: selectionModel.map { SelectionConfig(model: $0) })
        let retrievalFallback = selectionModel.map { _ in
            MetadataSearcher(index: index, mode: .retrieval, embedder: embedder)
        }
        self.searcher = searcher
        self.retrievalFallback = retrievalFallback
        following = Task {
            for await catalog in reloads {
                let entries = AgentSearchEntry.entries(of: catalog)
                await searcher.update(items: entries)
                await retrievalFallback?.update(items: entries)
            }
        }
    }

    /// Cancels the task that follows the reloads.
    deinit {
        following.cancel()
    }

    /// Searches the model-visible agents for `query`.
    ///
    /// When the selection tier fails and a retrieval fallback is there, the
    /// fallback ranks `query`. A cancellation is not a failure of the model,
    /// thus it always goes to the caller.
    ///
    /// - Parameters:
    ///   - query: The text of the search.
    ///   - limit: The most agents to give.
    /// - Returns: The ids of the matching agents, best first.
    /// - Throws: A cancellation, or the error of the retrieval fallback. With
    ///   no fallback, the error of the searcher.
    func search(query: String, limit: Int) async throws -> [String] {
        do {
            return try await searcher.search(intent: query, limit: limit).map(\.id)
        } catch {
            guard let retrievalFallback, !(error is CancellationError), !Task.isCancelled else {
                throw error
            }
            return try await retrievalFallback.search(intent: query, limit: limit).map(\.id)
        }
    }
}
