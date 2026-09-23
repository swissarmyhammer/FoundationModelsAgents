/// The shared environment of the four operations of the `agents` tool
/// (plan.md §9.1).
///
/// `AgentsTool.make(context:catalogCharacterLimit:)` reads the catalog of
/// `runner` one time. The operations use `runner` to start, check, and cancel
/// runs.
public struct AgentsToolContext: Sendable {
    /// The runner that owns each run that the tool starts.
    public let runner: AgentRunner

    /// The names of `Agent(a, b)`: the only agents that the tool can start.
    /// `nil` when the tool can start each model-visible agent.
    public let allowedNames: [String]?

    /// Makes a context.
    ///
    /// - Parameters:
    ///   - runner: The runner that owns each run that the tool starts.
    ///   - allowedNames: The names of `Agent(a, b)`, or `nil` for each
    ///     model-visible agent. The default is `nil`.
    public init(runner: AgentRunner, allowedNames: [String]? = nil) {
        self.runner = runner
        self.allowedNames = allowedNames
    }

    /// Tells whether the tool can start `definition`.
    ///
    /// - Parameter definition: An agent of the catalog.
    /// - Returns: `true` when the model can see the agent and the allowed
    ///   names, if any, hold its id.
    func canStart(_ definition: AgentDefinition) -> Bool {
        definition.isModelVisible && (allowedNames?.contains(definition.id) ?? true)
    }
}
