import Marketplace

/// What one catalog of an `AgentRegistry` holds, as lines that a host can
/// write (plan.md §10).
///
/// A host that follows `AgentRegistry.onReload` makes one report for each
/// catalog, and writes `lines`. Thus no host keeps its own copy of the counts
/// or of the words.
public struct AgentReloadReport: Sendable, Equatable {
    /// How many agents the catalog holds.
    public let agentCount: Int

    /// How many of those agents the model can see and start.
    public let modelVisibleCount: Int

    /// How many marketplace layers the build read.
    public let marketplaceLayerCount: Int

    /// How many agents of the catalog came from a marketplace layer.
    public let marketplaceAgentCount: Int

    /// The names of the slash commands of the catalog: the id of each
    /// user-invocable agent, sorted (plan.md §9.4). `AgentRunner` gives one
    /// command with each of these names.
    public let slashCommandNames: [String]

    /// How many diagnostics the catalog holds, for each severity. Each
    /// severity has a value, also when the count is zero.
    public let diagnosticCounts: [AgentDiagnostic.Severity: Int]

    /// What goes between two names of the command line.
    private static let nameSeparator = ", "

    /// Makes the report of one catalog.
    ///
    /// - Parameters:
    ///   - catalog: The catalog that `onReload` published.
    ///   - marketplaceLayers: The marketplace layers of the same build, for
    ///     example `AgentRegistry.marketplaceLayers`.
    public init(catalog: AgentCatalog, marketplaceLayers: [MarketplaceLayer]) {
        agentCount = catalog.definitions.count
        modelVisibleCount = catalog.modelVisible.count
        marketplaceLayerCount = marketplaceLayers.count
        marketplaceAgentCount = catalog.definitions.count { $0.marketplaceLayer != nil }
        slashCommandNames = catalog.userInvocable.map(\.id)
        diagnosticCounts = Dictionary(
            uniqueKeysWithValues: AgentDiagnostic.Severity.allCases.lazy.map { severity in
                (severity, catalog.diagnostics.count { $0.severity == severity })
            })
    }

    /// The lines of the report, in write order. No line ends with a line
    /// break.
    public var lines: [String] {
        [
            "reload: \(agentCount) agents, \(modelVisibleCount) model-visible",
            "marketplaces: \(marketplaceLayerCount) layers, \(marketplaceAgentCount) agents",
            "diagnostics: " + AgentDiagnostic.Severity.allCases.lazy.map { severity in
                "\(diagnosticCounts[severity, default: .zero]) \(severity.rawValue)"
            }.joined(separator: Self.nameSeparator),
            "commands: \(slashCommandNames.joined(separator: Self.nameSeparator))"
        ]
    }
}
