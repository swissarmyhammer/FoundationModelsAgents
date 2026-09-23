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

    /// A first argument that names no mode.
    case unknown(String)

    /// The flag of the watch mode.
    static let watchFlag = "--watch"

    /// The flag of the marketplace mode.
    static let marketplaceFlag = "--marketplace"

    /// The mode of each flag.
    private static let modes: [String: AgentsDemoMode] = [
        watchFlag: .watch,
        marketplaceFlag: .marketplace
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
        USAGE: agents-demo [\(AgentsDemoMode.watchFlag) | \(AgentsDemoMode.marketplaceFlag)]

        The example of the FoundationModelsAgents package, over Examples/agent-library.
        With no mode, the example writes this usage.

          \(AgentsDemoMode.watchFlag)        Write a reload report each time an agent file changes.
          \(AgentsDemoMode.marketplaceFlag)  List each agent with its provenance. The fixture
                         marketplace is a file:// source of a MarketplaceStore.
        """
}
