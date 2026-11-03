import Foundation
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing
import ULID

/// Pins the shared step of `AgentSessionMaker`: the instructions, the slot,
/// and the tools of a run come from one function
/// (``AgentSessionMaker/resolveSetup(for:family:)``). A new session and a
/// restored session both use it, thus a restore takes its tools and its
/// instructions from the current definition and catalog.
@Suite("The resolved setup of a run")
struct ResolvedSetupTests {
    /// Wraps `maker`: the new maker keeps each link in `record`, then gives
    /// the tool of `maker`.
    ///
    /// - Parameters:
    ///   - maker: The maker of the `agents` tool of a run.
    ///   - record: Keeps the links, in call order.
    /// - Returns: The maker that keeps each link.
    private static func wrapping(
        _ maker: @escaping AgentRunRequest.AgentsToolMaker, in record: CallRecord<AgentsToolContext.CallerLink?>
    ) -> AgentRunRequest.AgentsToolMaker {
        { parent, link, grant, allowedNames in
            record.add(link)
            return try await maker(parent, link, grant, allowedNames)
        }
    }

    /// The prompt of each request.
    private static let prompt = "resolved-setup-key: divide the task"

    /// Makes the shared step over `harness` and resolves `request`.
    ///
    /// - Parameters:
    ///   - request: The run.
    ///   - harness: The harness of the run.
    /// - Returns: The resolved setup.
    /// - Throws: The failure of the step.
    private static func resolve(
        _ request: AgentRunRequest, in harness: AgentRunHarness
    ) async throws -> AgentSessionMaker.ResolvedSetup {
        try await AgentSessionMaker(
            environment: harness.environment, renderer: AgentBodyRenderer(registry: harness.registry)
        ).resolveSetup(for: request, family: ParentRun.Family())
    }

    /// Makes a request of the lead agent, a restored caller, and a record of
    /// the links that its maker gets.
    ///
    /// - Parameters:
    ///   - harness: The harness of the run.
    ///   - caller: The session id of the restored caller, or `nil`.
    /// - Returns: The request and the record.
    /// - Throws: The error of `#require` when the registry has no lead.
    private static func leadRequest(
        in harness: AgentRunHarness, restoredCaller caller: ULID?
    ) throws -> (request: AgentRunRequest, links: CallRecord<AgentsToolContext.CallerLink?>) {
        let links = CallRecord<AgentsToolContext.CallerLink?>()
        var request = try harness.request(
            NestedRunTests.lead, prompt: prompt,
            agentsTool: wrapping(AgentRun.agentsTool(of: harness.makeRunner()), in: links))
        request.restoredCaller = caller
        return (request, links)
    }

    @Test("the setup of a request with a restored caller gives the maker a link with the session id of that caller")
    func restoredCallerLinkHasTheSessionID() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let caller = ULID()
        let (request, links) = try Self.leadRequest(in: harness, restoredCaller: caller)

        _ = try await Self.resolve(request, in: harness)

        #expect(links.all.first??.sessionID == caller)
    }

    @Test("the setup of a request with a restored caller gives the maker a link with the mail route")
    func restoredCallerLinkHasTheMailRoute() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let (request, links) = try Self.leadRequest(in: harness, restoredCaller: ULID())

        _ = try await Self.resolve(request, in: harness)

        let route = try #require(links.all.first ?? nil).route
        let isMail: Bool
        if case .mail = route { isMail = true } else { isMail = false }
        #expect(isMail)
    }

    @Test("the setup of a request with no caller gives the maker no link")
    func noCallerGivesNoLink() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let (request, links) = try Self.leadRequest(in: harness, restoredCaller: nil)

        _ = try await Self.resolve(request, in: harness)

        #expect(links.all.count == 1)
        #expect(links.all.first! == nil)
    }

    @Test("the instructions of the setup hold the AGENTS.md text of the working folder")
    func instructionsHoldAgentsMd() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let (request, _) = try Self.leadRequest(in: harness, restoredCaller: nil)

        let setup = try await Self.resolve(request, in: harness)

        #expect(setup.instructions.contains(AgentRunHarness.agentsMdText))
    }

    @Test("the slot of the setup is the default slot for an agent with no model")
    func slotIsTheDefaultSlot() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let (request, _) = try Self.leadRequest(in: harness, restoredCaller: nil)

        let setup = try await Self.resolve(request, in: harness)

        #expect(setup.slot == harness.environment.defaultSlot)
    }
}
