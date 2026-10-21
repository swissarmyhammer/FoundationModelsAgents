import Synchronization

/// The parts of the `agents` endpoint that one ``AgentRegistry`` has one time
/// (EXTRAS-9 rule 1): the endpoint is made once per port, not once per tool.
///
/// The registry owns its port. The first ``endpoint()`` call makes the
/// ``AgentsGraph``, and each later call gives the same instance. Thus each
/// ``AgentsTool`` over the registry, of each session and each run, gives the
/// same endpoint. The change log of the `changes(after:)` subscription is one
/// per registry too: it is in the current build, thus each endpoint over the
/// registry gives the same cursor.
///
/// The endpoint reads the current build of the registry
/// (``AgentRegistry/CurrentBuild``), never the registry itself. Thus the port
/// keeps no reference back to the registry, and the host still releases the
/// registry.
final class AgentsGraphPort: Sendable {
    /// The current build of the registry that owns the port.
    private let build: AgentRegistry.CurrentBuild

    /// The endpoint, or `nil` before the first ``endpoint()`` call.
    private let made = Mutex<AgentsGraph?>(nil)

    /// Makes the port of a registry. It makes no endpoint yet.
    ///
    /// - Parameter build: The current build of the registry that owns the
    ///   port.
    init(build: AgentRegistry.CurrentBuild) {
        self.build = build
    }

    /// Gives the one endpoint of the registry. The first call builds its
    /// schema; each later call gives the same instance.
    ///
    /// - Returns: The endpoint.
    /// - Throws: An error of the schema builder. A later call tries again.
    func endpoint() throws -> AgentsGraph {
        try made.withLock { made in
            if let endpoint = made {
                return endpoint
            }
            let endpoint = try AgentsGraph(build: build)
            made = endpoint
            return endpoint
        }
    }
}
