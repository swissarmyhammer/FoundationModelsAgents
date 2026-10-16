import FoundationModelsExtras

/// An embedder that sends each batch of texts that it embeds to ``batches``,
/// then embeds the batch as ``ScriptedEmbeddingContainer`` does.
///
/// A test reads ``batches`` to know when a search index embeds a new catalog.
/// `MetadataSearcher.update(items:)` puts the new index in place before it
/// embeds the new entries. Thus a batch that holds the text of an agent tells
/// that a search can find that agent. The test needs no wall-clock wait.
struct SignalingEmbedder: PooledEmbedding {
    /// Each batch of texts that the embedder embeds, in call order.
    let batches: AsyncStream<[String]>

    /// The continuation of ``batches``.
    private let continuation: AsyncStream<[String]>.Continuation

    /// The embedder that gives the vectors.
    private let vectors = ScriptedEmbeddingContainer()

    /// Makes an embedder with an empty stream of batches.
    init() {
        (batches, continuation) = AsyncStream<[String]>.makeStream()
    }

    /// Sends `texts` to ``batches``, then gives the vectors of
    /// ``ScriptedEmbeddingContainer``.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: One vector for each text, in the order of `texts`.
    /// - Throws: Never in practice: the scripted container does not throw.
    func embed(texts: [String]) async throws -> [[Float]] {
        continuation.yield(texts)
        return try await vectors.embed(texts: texts)
    }
}
