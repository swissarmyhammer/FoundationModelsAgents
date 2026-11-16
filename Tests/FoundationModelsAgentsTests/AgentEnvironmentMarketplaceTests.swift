import FoundationModels
import FoundationModelsAgents
import FoundationModelsSkills
import Marketplace
import Testing

/// Pins that `AgentEnvironment.make` gives the marketplace list of the host to
/// the `skills` tool.
@Suite("Agent environment marketplaces")
struct AgentEnvironmentMarketplaceTests {
    /// The id of the one marketplace of the fixture list.
    static let acmeID = "acme"

    /// The source URL of the one marketplace of the fixture list.
    static let acmeURL = "github:acme/skills"

    /// The text of the `list marketplace` answer that names the marketplace.
    static let acmeLine = "`\(acmeID)`: \(acmeURL)"

    /// The arguments of a `list marketplace` call.
    static let listMarketplace = GeneratedContent(properties: ["op": "list marketplace"])

    /// A marketplace list that has only the marketplace ``acmeID``.
    ///
    /// - Returns: The registry.
    static func acmeMarketplaces() -> MarketplaceRegistry {
        MarketplaceRegistry(
            storage: InMemoryMarketplaceSourceStorage(sources: [MarketplaceSource(acmeURL, alias: acmeID)]))
    }

    /// With no selection model, the `skills` tool has the marketplace
    /// operations of the list that `make` gets.
    @Test("A marketplace list gives the keyword skills tool the marketplace operations")
    func keywordToolListsTheMarketplaces() async throws {
        let profile = try await AgentEnvironmentTests.makeProfile()

        let environment = try await AgentEnvironment.make(
            profile: profile, skills: SkillsRegistry.makeEmpty(), skillsMarketplaces: Self.acmeMarketplaces())

        let answer = try await environment.skillsTool.call(arguments: Self.listMarketplace)
        #expect(answer.contains(Self.acmeLine))
    }

    /// With a selection model, the `skills` tool has the marketplace
    /// operations of the list that `make` gets.
    @Test("A marketplace list gives the selection skills tool the marketplace operations")
    func selectionToolListsTheMarketplaces() async throws {
        let profile = try await AgentEnvironmentTests.makeProfile()

        let environment = try await AgentEnvironment.make(
            profile: profile, skills: SkillsRegistry.makeEmpty(),
            skillsSelectionModel: SelectionProbeModel(calls: SelectionProbeCalls()),
            skillsMarketplaces: Self.acmeMarketplaces())

        let answer = try await environment.skillsTool.call(arguments: Self.listMarketplace)
        #expect(answer.contains(Self.acmeLine))
    }

    /// With no marketplace list, the `skills` tool has no marketplace
    /// operation.
    @Test("No marketplace list gives the skills tool no marketplace operation")
    func noListGivesNoMarketplaceOperation() async throws {
        let profile = try await AgentEnvironmentTests.makeProfile()

        let environment = try await AgentEnvironment.make(profile: profile, skills: SkillsRegistry.makeEmpty())

        let answer = try await environment.skillsTool.call(arguments: Self.listMarketplace)
        #expect(!answer.contains(Self.acmeLine))
    }
}
