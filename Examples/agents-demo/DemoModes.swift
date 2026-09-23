import FoundationModelsAgents

/// The receiver of each line that a mode writes.
///
/// The binary gives a closure that writes the line with `StandardStream`. A
/// test gives a closure that keeps the line.
typealias AgentsDemoOutput = @Sendable (String) -> Void

/// The work of each mode of `agents-demo` that needs no profile (plan.md §13).
///
/// Each function takes its registry and its output. Thus a test calls it with
/// no process.
enum AgentsDemoModes {
    /// Loads the registry, then writes one `AgentReloadReport` for each
    /// catalog that `onReload` publishes, the catalog of the load too.
    ///
    /// The function takes `onReload` before `load()`, thus it gets each
    /// catalog. It returns when the task is cancelled, or when the stream
    /// ends.
    ///
    /// - Parameters:
    ///   - registry: The registry to watch. Make it with `watch: true` to get
    ///     a report for each change of a layer root.
    ///   - output: The receiver of each report line.
    /// - Throws: The error of the first `load()`.
    static func watch(registry: AgentRegistry, output: AgentsDemoOutput) async throws {
        let reloads = registry.onReload
        try await registry.load()
        for await catalog in reloads {
            let report = AgentReloadReport(catalog: catalog, marketplaceLayers: registry.marketplaceLayers)
            for line in report.lines {
                output(line)
            }
        }
    }

    /// Loads the registry, then writes one line for each agent: its id and
    /// its provenance.
    ///
    /// - Parameters:
    ///   - registry: The registry to list, for example a registry over a
    ///     marketplace store.
    ///   - output: The receiver of each line.
    /// - Throws: The error of `load()`.
    static func marketplace(registry: AgentRegistry, output: AgentsDemoOutput) async throws {
        try await registry.load()
        for definition in registry.catalog().definitions {
            output(provenanceLine(of: definition))
        }
    }

    /// The line of one agent: `<id>: marketplace <marketplace>` for an agent
    /// of a marketplace layer, else `<id>: local <layer source>`.
    ///
    /// - Parameter definition: The agent.
    /// - Returns: The line of the agent.
    static func provenanceLine(of definition: AgentDefinition) -> String {
        guard let marketplace = definition.marketplace else {
            return "\(definition.id): local \(definition.layer.source)"
        }
        return "\(definition.id): marketplace \(marketplace.displayText)"
    }
}
