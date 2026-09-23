// The entry point of `agents-demo`, the example of plan.md §13.
//
// With no mode, the example writes the usage to standard output. Each mode of
// plan.md §13 adds one flag to `AgentsDemoUsage.text` when a later task makes
// that mode.

import FoundationModelsSkills

/// The usage text of `agents-demo`.
enum AgentsDemoUsage {
    /// The text that `agents-demo` writes when it gets no mode.
    static let text = """
        USAGE: agents-demo

        The example of the FoundationModelsAgents package.
        This build has no mode. It writes this usage only.
        """
}

StandardStream.output.write(line: AgentsDemoUsage.text)
