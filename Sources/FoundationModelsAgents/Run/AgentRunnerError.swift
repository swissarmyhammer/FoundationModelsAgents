/// An error of `AgentRunner` that stops a run before it starts
/// (plan.md §9.3).
public enum AgentRunnerError: Error, Sendable, Equatable {
    /// The catalog has no agent with the name.
    ///
    /// - Parameters:
    ///   - name: The name that the caller gave.
    ///   - available: The id of each agent of the catalog, sorted. It is
    ///     empty when the host did not call `AgentRegistry.load()`.
    case unknownAgent(name: String, available: [String])
}
