import FoundationModelsRouter
import Testing
import ULID

@testable import FoundationModelsAgents

/// Pins the self rule of the `agents` tool of a run.
///
/// The tool of a run does not list the agent of that run, cannot start it,
/// and cannot send a message to the run itself. Thus a model of a run cannot
/// match its own entry in the list and give its own task to a new run of its
/// own agent. A host root session has no run, and the rule does not apply to
/// it (`AgentsToolDescriptionTests` pins the full list of a host tool).
@Suite("Agents tool self rule")
struct AgentsToolSelfRuleTests {
    /// The agent of the run that holds the tool in these tests.
    private static let ownAgent = "code-reviewer"

    /// An other agent of the fixture library that the tool can start.
    private static let otherAgent = "lead"

    /// The prompt of a `start agent` call of these tests.
    private static let prompt = "self-rule-key: review the parser"

    /// The message of a `send agent` call of these tests.
    private static let message = "Also check the error paths."

    /// The agents that the tool of the run can start, in catalog order.
    private static let startableNames = ["internal-helper", "lead", "test-writer"]

    /// The key of the play of the root session that gives the call context.
    private static let rootKey = "self-rule-root-key"

    /// The prompt and the answer of the root session.
    private static let rootText = "Start the review."

    /// The prompt of the run that the probe starts. It is also the key of
    /// its play.
    private static let childPrompt = "self-rule-child-key: review the parser"

    /// The step of the root session that calls the probe tool.
    private static let probeStep = ScriptedAgentStep.toolCall(
        name: AgentStartProbe.toolName, argumentsJSON: #"{"text":"start"}"#)

    /// Makes the harness of a tool of a run of ``ownAgent``.
    ///
    /// - Parameter script: The script of the profile.
    /// - Returns: The harness. The test deletes it.
    /// - Throws: The error of the run harness, or of `AgentsTool.make`.
    private static func makeRunToolHarness(
        script: ScriptedAgentScript = ScriptedAgentScript([])
    ) async throws -> AgentsToolHarness {
        let runHarness = try await AgentRunHarness.make(script: script)
        let runner = runHarness.makeRunner()
        let parent = ParentRun(depth: AgentRunner.hostDepth, slot: .standard, agentID: ownAgent, family: ParentRun.Family())
        do {
            let tool = try await AgentsTool.make(
                context: AgentsToolContext(
                    runner: runner, allowedNames: nil, parent: parent, callerLink: nil, grant: .full))
            return AgentsToolHarness(runHarness: runHarness, runner: runner, tool: tool)
        } catch {
            try? runHarness.delete()
            throw error
        }
    }

    @Test func theDescriptionOfTheToolOfARunDoesNotListItsOwnAgent() async throws {
        let harness = try await Self.makeRunToolHarness()
        defer { try? harness.delete() }

        let description = harness.tool.description

        #expect(!description.contains("- \(Self.ownAgent)"))
        #expect(description.contains("- \(Self.otherAgent): "))
    }

    @Test func listAgentsInTheToolOfARunDoesNotGiveItsOwnAgent() async throws {
        let harness = try await Self.makeRunToolHarness()
        defer { try? harness.delete() }

        let answer = try await harness.call("list agents")

        #expect(!answer.contains("- \(Self.ownAgent)"))
        #expect(answer.contains("- \(Self.otherAgent): "))
    }

    @Test func startAgentWithTheOwnAgentGivesTheOwnAgentCorrectiveAndStartsNoRun() async throws {
        let harness = try await Self.makeRunToolHarness()
        defer { try? harness.delete() }

        let answer = try await harness.call("start agent", ["name": Self.ownAgent, "prompt": Self.prompt])

        #expect(answer == AgentsToolText.ownAgent(Self.ownAgent, available: Self.startableNames))
        #expect(await harness.runner.runs.isEmpty)
    }

    @Test("send agent with the id of the own run gives the own-run corrective", .timeLimit(.minutes(1)))
    func sendAgentToTheOwnRunGivesTheOwnRunCorrective() async throws {
        let harness = try await Self.makeRunToolHarness(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: Self.rootKey, steps: [Self.probeStep, .finalText(Self.rootText)]),
                ScriptedAgentPlay(key: Self.childPrompt, steps: [.finalText(Self.rootText)])
            ]))
        defer { try? harness.delete() }
        let probe = AgentStartProbe { context in
            try await harness.runHarness.start(AgentRunTests.reviewer, prompt: Self.childPrompt, context: context)
        }
        let session = AgentRunHarness.makeRootSession(
            on: harness.runHarness.profile.standard, instructions: Self.rootKey, tools: [probe])
        _ = try await session.respond(to: Self.rootText)
        let started = try #require(probe.started)
        _ = await started.run.finalState()
        await session.close()
        let call = try #require(started.context)
        let ownID = session.id.description

        let answer = try await ToolContext.$current.withValue(call) {
            try await harness.call("send agent", ["id": ownID, "message": Self.message])
        }

        #expect(answer == AgentsToolText.ownRun(ownID))
    }
}
