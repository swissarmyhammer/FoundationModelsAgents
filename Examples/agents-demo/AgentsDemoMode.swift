import FoundationModelsSkills

/// The mode of one run of `agents-demo` (plan.md §13).
///
/// The first argument selects the mode. The example reads no other argument.
enum AgentsDemoMode: Equatable {
    /// No argument: the example writes the usage.
    case usage

    /// `--watch`: the example writes one reload report for each catalog.
    case watch

    /// `--marketplace`: the example lists each agent with its provenance.
    case marketplace

    /// `--chat`: a root Router session with the `agents` tool starts the
    /// `lead` agent, and `lead` starts two agents. It needs a resolved
    /// profile.
    case chat

    /// `--fan-out`: two host-driven runs, one on each generation slot, at the
    /// same time. It needs a resolved profile.
    case fanOut

    /// A first argument that names no mode.
    case unknown(String)

    /// The flag of the watch mode.
    static let watchFlag = "--watch"

    /// The flag of the marketplace mode.
    static let marketplaceFlag = "--marketplace"

    /// The flag of the chat mode.
    static let chatFlag = "--chat"

    /// The flag of the fan-out mode.
    static let fanOutFlag = "--fan-out"

    /// The mode of each flag.
    private static let modes: [String: AgentsDemoMode] = [
        watchFlag: .watch,
        marketplaceFlag: .marketplace,
        chatFlag: .chat,
        fanOutFlag: .fanOut
    ]

    /// Reads the mode from the arguments of the process.
    ///
    /// - Parameter arguments: The arguments, with no executable name.
    init(arguments: [String]) {
        guard let flag = arguments.first else {
            self = .usage
            return
        }
        self = Self.modes[flag] ?? .unknown(flag)
    }
}

/// The usage text of `agents-demo`.
enum AgentsDemoUsage {
    /// The text that `agents-demo` writes when it gets no mode.
    static let text = """
        USAGE: agents-demo [\(AgentsDemoMode.watchFlag) | \(AgentsDemoMode.marketplaceFlag) | \
        \(AgentsDemoMode.chatFlag) | \(AgentsDemoMode.fanOutFlag)]

        The example of the FoundationModelsAgents package, over Examples/agent-library.
        With no mode, the example writes this usage.

          \(AgentsDemoMode.watchFlag)        Write a reload report each time an agent file changes.
          \(AgentsDemoMode.marketplaceFlag)  List each agent with its provenance. The fixture
                         marketplace is a file:// source of a MarketplaceStore.
          \(AgentsDemoMode.chatFlag)         A root session with the agents tool starts the lead
                         agent, and lead starts code-reviewer and test-writer.
          \(AgentsDemoMode.fanOutFlag)      Run code-reviewer (flash) and test-writer (standard)
                         at the same time, and write both results.

        \(AgentsDemoMode.chatFlag) and \(AgentsDemoMode.fanOutFlag) resolve a real profile of small
        mlx-community models. The first run downloads the models.
        """
}
