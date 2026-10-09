/// An error of `AgentRunner` that stops a run before it starts.
public enum AgentRunnerError: Error, Sendable, Equatable {
    /// The catalog has no agent with the name.
    ///
    /// - Parameters:
    ///   - name: The name that the caller gave.
    ///   - available: The id of each agent of the catalog, sorted.
    case unknownAgent(name: String, available: [String])

    /// The host called ``AgentRunner/stop()``. After that call, the runner
    /// starts no run.
    case stopped

    /// The host did not call `AgentRegistry.load()` or
    /// `AgentRegistry.reload()` before this call. Until the first build of
    /// the registry, the catalog is empty, thus the runner cannot find an
    /// agent. ``AgentsTool/make(context:catalogCharacterLimit:)`` throws
    /// this error too.
    case catalogNotLoaded
}
