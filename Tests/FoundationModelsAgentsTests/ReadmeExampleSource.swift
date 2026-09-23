import Foundation
import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import FoundationModelsSkills
import Marketplace

/// The compiled copy of the Swift example of `README.md` (plan.md §12, §15).
///
/// The text between the two marker comments in ``run(profile:folders:)`` is
/// the README block, line for line. `ReadmeExampleTests` compares the two
/// texts, and runs this copy with a scripted profile. Thus the README cannot
/// hold code that does not compile, or code that does not run.
enum ReadmeExampleSource {
    /// The folders that the example reads. The README names each one as a
    /// variable of the host.
    struct Folders {
        /// The working directory of the project. Its project layer is
        /// `.agents/`, and the runs work in it.
        let projectDirectory: URL

        /// The `defaults` layer of the agent files that the host ships.
        let shippedAgentsURL: URL

        /// The `defaults` layer of the skill folders that the host ships.
        let shippedSkillsURL: URL

        /// The `user` layer of the agent files and of the skill folders.
        let userConfigURL: URL

        /// The location of the git repository of the marketplace, for
        /// example an HTTPS URL that ends in `.git`, or a `file://` URL.
        let marketplaceURL: String

        /// The cache folder of the marketplace store.
        let cacheDirectory: URL
    }

    /// What the example gives back to the test.
    struct Outcome {
        /// The listing of the catalog after `load()`.
        let listing: [AgentListing]

        /// The final text of the host-driven run.
        let review: String

        /// The answer of the turn that reads the final message of the
        /// model-driven run.
        let answer: String?
    }

    /// Runs the README example.
    ///
    /// - Parameters:
    ///   - profile: The resolved profile of the host Router.
    ///   - folders: The folders that the example reads.
    /// - Returns: The listing, the result of the host-driven run, and the
    ///   answer of the root session after the model-driven run.
    /// - Throws: The error of `load()`, of a tool, of a run, or of a turn.
    static func run(profile: LanguageModelProfile, folders: Folders) async throws -> Outcome {
        let projectDirectory = folders.projectDirectory
        let shippedAgentsURL = folders.shippedAgentsURL
        let shippedSkillsURL = folders.shippedSkillsURL
        let userConfigURL = folders.userConfigURL
        let marketplaceURL = folders.marketplaceURL
        let cacheDirectory = folders.cacheDirectory

        // README example: begin
        // The host makes the dependencies: two dotfolder stacks and one marketplace store.
        let agentStack = DotfolderStack(
            name: "agents",
            workingDirectory: projectDirectory,
            defaultsDirectory: shippedAgentsURL,
            userDirectory: userConfigURL)
        let skillStack = DotfolderStack(
            name: "skills",
            workingDirectory: projectDirectory,
            defaultsDirectory: shippedSkillsURL,
            userDirectory: userConfigURL)
        let market = MarketplaceStore(
            sources: [MarketplaceSource(marketplaceURL)],
            layout: SkillMarketplaceLayout.skills,
            cacheDirectory: cacheDirectory)

        // The registry init reads no file. Start the store, then load the catalog.
        let registry = AgentRegistry(
            marketplaces: market, stack: agentStack, variables: ["project": "acme"], watch: true)
        await market.start()
        try await registry.load()
        let listing = registry.catalog().listing   // [AgentListing], one for each agent

        // Skills are separate from agents. An agent uses skills through its
        // `skills:` preload and through the `skills` tool.
        let skills = SkillsRegistry(marketplaces: market, stack: skillStack, watch: true)
        let skillsTool = try await SkillsTool.make(registry: skills)
        var tools = ToolCatalog()
        tools.register("skills") { skillsTool }

        let environment = AgentEnvironment(
            profile: profile, skills: skills, workingDirectory: projectDirectory, tools: tools)
        let runner = AgentRunner(registry: registry, environment: environment)

        // Host-driven: start a run, then wait for its final text.
        let run = try await runner.start("security-reviewer", prompt: "Review Sources/Parser.swift.")
        let review = try await run.result()

        // Model-driven: a root Router session gets the agents tool.
        let agentsTool = try await AgentsTool.make(context: AgentsToolContext(runner: runner))
        let root = profile.standard.makeSession(
            instructions: "You give work to agents with the agents tool.",
            workingDirectory: projectDirectory,
            tools: [agentsTool])
        let events = await root.streamSessionEvents()   // subscribe before the first turn
        for try await _ in await root.streamEvents(to: "Ask code-reviewer to review Sources/Parser.swift.") {}

        // `start agent` returns at once. When the run ends, its final message
        // is staged in the root session, and the next turn reads it.
        _ = await events.first { event in
            if case .runSettled = event { true } else { false }
        }
        let answer = try await root.dispatchNextPrompt()

        // The Router does not know the runs of a session: cancel them before close().
        await runner.cancelRuns(caller: root.id)
        await root.close()
        // README example: end

        return Outcome(listing: listing, review: review, answer: answer)
    }
}
