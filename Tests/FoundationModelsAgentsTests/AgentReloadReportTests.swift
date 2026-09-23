@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins `AgentReloadReport` (plan.md §10) on the fixture library and the
/// fixture marketplace.
@Suite("Agent reload report")
struct AgentReloadReportTests {
    /// The agents of the fixture library that the model cannot see:
    /// release-manager has `disable-model-invocation: true`.
    private static let modelHiddenIDs: Set = ["release-manager"]

    /// The count of the marketplace layers of the fixture provider.
    private static let fixtureMarketplaceLayerCount = 1

    /// The advisories of the fixture library and the fixture marketplace:
    /// the defaults copy and the user copy of code-reviewer are hidden.
    private static let fixtureAdvisoryCount = 2

    /// The slash command names that a row gives to the report.
    private static let commandNames = ["code-reviewer", "test-writer"]

    @Test("the counts match the fixture library and the fixture marketplace")
    func countsMatchTheFixtureLibrary() async throws {
        let provider = try await FixtureMarketplaceProvider.make()
        defer { try? provider.delete() }
        let registry = AgentRegistry(marketplaces: provider, stack: FixtureLibrary.stack())
        let catalog = try await registry.loadedCatalog()

        let report = AgentReloadReport(catalog: catalog, marketplaceLayers: registry.marketplaceLayers)

        let agentIDs = FixtureLibrary.localAgentIDs.union(FixtureMarketplaceProvider.agentIDs)
        #expect(report.agentCount == agentIDs.count)
        #expect(report.modelVisibleCount == agentIDs.subtracting(Self.modelHiddenIDs).count)
        #expect(report.marketplaceLayerCount == Self.fixtureMarketplaceLayerCount)
        #expect(report.marketplaceAgentCount == FixtureMarketplaceProvider.agentIDs.count)
        #expect(report.slashCommandNames.isEmpty)
        #expect(
            report.diagnosticCounts == [.advisory: Self.fixtureAdvisoryCount, .warning: .zero, .skip: .zero])
    }

    @Test("an empty catalog gives a zero count for each severity")
    func emptyCatalogGivesZeroCounts() {
        let report = AgentReloadReport(
            catalog: AgentCatalog(definitions: [], diagnostics: []), marketplaceLayers: [])

        #expect(report.agentCount == .zero)
        #expect(report.diagnosticCounts == [.advisory: .zero, .warning: .zero, .skip: .zero])
    }

    @Test("the lines name each count and each command")
    func linesNameEachCount() async throws {
        let provider = try await FixtureMarketplaceProvider.make()
        defer { try? provider.delete() }
        let registry = AgentRegistry(marketplaces: provider, stack: FixtureLibrary.stack())
        let catalog = try await registry.loadedCatalog()

        let report = AgentReloadReport(
            catalog: catalog, marketplaceLayers: registry.marketplaceLayers, slashCommandNames: Self.commandNames)

        #expect(
            report.lines == [
                "reload: 7 agents, 6 model-visible",
                "marketplaces: 1 layers, 2 agents",
                "diagnostics: 2 advisory, 0 warning, 0 skip",
                "commands: code-reviewer, test-writer"
            ])
    }
}
