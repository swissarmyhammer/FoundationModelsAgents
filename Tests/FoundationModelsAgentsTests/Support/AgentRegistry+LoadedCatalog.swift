@testable import FoundationModelsAgents

extension AgentRegistry {
    /// Loads the registry, then gives its catalog.
    ///
    /// Each `init` of `AgentRegistry` reads no file, thus a test calls
    /// `load()` before it reads `catalog()`.
    ///
    /// - Returns: The catalog of the first build.
    /// - Throws: The error of `load()`.
    func loadedCatalog() async throws -> AgentCatalog {
        try await load()
        return catalog()
    }
}
