import Foundation
import FoundationModelsAgents
import FoundationModelsRouter
import FoundationModelsSkills
import Testing

/// Pins the defaults and the limits of `AgentEnvironment` (plan.md §3, §7).
@Suite("Agent environment")
struct AgentEnvironmentTests {
    /// The token count that the budget tests give to `budget`.
    static let contextTokens = 8192

    /// A value for each limit that is not its default.
    static let customLimit = 7

    /// A limit that is below the lowest value that the environment accepts.
    static let limitBelowRange = -1

    /// The depth limit that plan.md §1 states.
    static let planMaxDepth = 3

    /// The name of the one tool of the custom tool catalog.
    static let probeToolName = "Read"

    /// Makes a skills registry with no layers.
    ///
    /// - Returns: A registry that holds no skill.
    static func makeEmptySkills() -> SkillsRegistry {
        SkillsRegistry(roots: [])
    }

    /// Resolves a scripted profile with no plays.
    ///
    /// - Returns: The profile.
    /// - Throws: Whatever `ScriptedProfile.make` throws.
    static func makeProfile() async throws -> LanguageModelProfile {
        let (_, profile) = try await ScriptedProfile.make(script: ScriptedAgentScript([]))
        return profile
    }

    /// An environment with only the profile and the skills registry gets the
    /// defaults of plan.md §3 and §7.
    @Test("The defaults are the plan values")
    func defaultsAreThePlanValues() async throws {
        let profile = try await Self.makeProfile()

        let environment = AgentEnvironment(profile: profile, skills: Self.makeEmptySkills())

        #expect(environment.profile === profile)
        #expect(environment.workingDirectory == URL.currentDirectory())
        #expect(environment.tools.names.isEmpty)
        #expect(environment.defaultSlot == .standard)
        #expect(environment.maxConcurrentAgents == AgentEnvironment.defaultMaxConcurrentAgents)
        #expect(environment.maxDepth == AgentEnvironment.defaultMaxDepth)
        #expect(environment.maxDepth == Self.planMaxDepth)
        #expect(environment.maxRetainedRuns == AgentEnvironment.defaultMaxRetainedRuns)
        #expect(environment.budget(Self.contextTokens) == TokenBudget(limit: Self.contextTokens))
    }

    /// Each value that the host gives replaces its default.
    @Test("Each given value replaces its default")
    func givenValuesReplaceDefaults() async throws {
        let profile = try await Self.makeProfile()
        let directory = FileManager.default.temporaryDirectory
        var tools = ToolCatalog()
        tools.register(Self.probeToolName) { ProbeTool(name: Self.probeToolName) }

        let environment = AgentEnvironment(
            profile: profile, skills: Self.makeEmptySkills(), workingDirectory: directory,
            tools: tools, defaultSlot: .flash, maxConcurrentAgents: Self.customLimit,
            maxDepth: Self.customLimit, maxRetainedRuns: Self.customLimit,
            budget: { _ in nil })

        #expect(environment.workingDirectory == directory)
        #expect(environment.tools.names == [Self.probeToolName])
        #expect(environment.defaultSlot == .flash)
        #expect(environment.maxConcurrentAgents == Self.customLimit)
        #expect(environment.maxDepth == Self.customLimit)
        #expect(environment.maxRetainedRuns == Self.customLimit)
        #expect(environment.budget(Self.contextTokens) == nil)
    }

    /// The lowest valid value of each limit makes an environment: one
    /// running agent, depth one, and no retained run record.
    @Test("The lowest valid limits make an environment")
    func lowestValidLimitsMakeAnEnvironment() async throws {
        let profile = try await Self.makeProfile()

        let environment = AgentEnvironment(
            profile: profile, skills: Self.makeEmptySkills(), maxConcurrentAgents: 1,
            maxDepth: 1, maxRetainedRuns: 0)

        #expect(environment.maxConcurrentAgents == 1)
        #expect(environment.maxDepth == 1)
        #expect(environment.maxRetainedRuns == 0)
    }

    /// The `embedding` slot makes no session, thus it is not a default slot.
    @Test("The embedding slot is not a default slot")
    func embeddingDefaultSlotStopsTheProcess() async {
        await #expect(processExitsWith: .failure) {
            let profile = try await Self.makeProfile()
            _ = AgentEnvironment(
                profile: profile, skills: Self.makeEmptySkills(), defaultSlot: .embedding)
        }
    }

    /// Zero running agents would stop each start, thus it is not a limit.
    @Test("maxConcurrentAgents is at least one")
    func zeroConcurrentAgentsStopsTheProcess() async {
        await #expect(processExitsWith: .failure) {
            let profile = try await Self.makeProfile()
            _ = AgentEnvironment(
                profile: profile, skills: Self.makeEmptySkills(), maxConcurrentAgents: 0)
        }
    }

    /// A host-started run has depth one, thus a depth of zero is not a limit.
    @Test("maxDepth is at least one")
    func zeroDepthStopsTheProcess() async {
        await #expect(processExitsWith: .failure) {
            let profile = try await Self.makeProfile()
            _ = AgentEnvironment(profile: profile, skills: Self.makeEmptySkills(), maxDepth: 0)
        }
    }

    /// A negative count of retained runs is not a limit.
    @Test("maxRetainedRuns is not negative")
    func negativeRetainedRunsStopsTheProcess() async {
        await #expect(processExitsWith: .failure) {
            let profile = try await Self.makeProfile()
            _ = AgentEnvironment(
                profile: profile, skills: Self.makeEmptySkills(),
                maxRetainedRuns: Self.limitBelowRange)
        }
    }
}
