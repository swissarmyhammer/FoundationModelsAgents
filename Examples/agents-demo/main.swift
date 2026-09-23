// The entry point of `agents-demo`, the example of plan.md §13.
//
// With no mode, the example prints the usage. Each mode of plan.md §13 adds
// one flag to `AgentsDemoUsage.text` when a later task makes that mode.

/// The usage text of `agents-demo`.
enum AgentsDemoUsage {
    /// The text that `agents-demo` prints when it gets no mode.
    static let text = """
        USAGE: agents-demo

        The example of the FoundationModelsAgents package.
        This build has no mode. It prints this usage only.
        """
}

print(AgentsDemoUsage.text)
