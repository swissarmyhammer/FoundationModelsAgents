import Foundation
import FoundationModels
@testable import FoundationModelsAgents
import Testing

/// Pins one key for the agent of `start agent` and `schedule agent`: each op
/// takes `name` and `agent` for it, and refuses two different values.
///
/// A call with no `op` whose fields fit `start agent` alone, a `prompt` and
/// an agent name, starts the agent. A call whose fields fit no op alone
/// keeps the corrective of an unknown op.
///
/// Seen live in the bench run planner24: the model sent
/// `{"op": "start agent", "agent": "planner", "prompt": "..."}` and got
/// "Missing required parameter(s): name.", because `schedule agent` names
/// its agent `agent` in the same fused schema.
@Suite("Forgiving agent name")
struct ForgivingAgentNameTests {
    /// A model-visible agent of the fixture library.
    private static let agent = "code-reviewer"

    /// A second model-visible agent of the fixture library.
    private static let otherAgent = "test-writer"

    /// The prompt of each call.
    private static let prompt = "forgiving-name: review the change"

    /// Makes a harness whose runs end at once.
    ///
    /// - Returns: The harness.
    private static func harness() async throws -> AgentsToolHarness {
        try await AgentsToolHarness.make(
            script: ScriptedAgentScript([ScriptedAgentPlay(key: prompt, steps: [.finalText("reviewed")])]))
    }

    @Test("start agent with agent in place of name starts the agent")
    func startAgentTakesAgent() async throws {
        let harness = try await Self.harness()
        defer { try? harness.delete() }

        let answer = try await harness.call("start agent", ["agent": Self.agent, "prompt": Self.prompt])

        #expect(answer.hasPrefix("Agent \(Self.agent) started with the id"), "\(answer)")
    }

    @Test("start agent with subagent_type in place of name starts the agent")
    func startAgentTakesSubagentType() async throws {
        let harness = try await Self.harness()
        defer { try? harness.delete() }

        let answer = try await harness.call("start agent", ["subagent_type": Self.agent, "prompt": Self.prompt])

        #expect(answer.hasPrefix("Agent \(Self.agent) started with the id"), "\(answer)")
    }

    @Test("start agent with the same name and agent starts the agent")
    func sameNameAndAgent() async throws {
        let harness = try await Self.harness()
        defer { try? harness.delete() }

        let answer = try await harness.call(
            "start agent", ["name": Self.agent, "agent": Self.agent, "prompt": Self.prompt])

        #expect(answer.hasPrefix("Agent \(Self.agent) started with the id"), "\(answer)")
    }

    @Test("start agent with a different name and agent is refused, and starts no run")
    func differentNameAndAgent() async throws {
        let harness = try await Self.harness()
        defer { try? harness.delete() }

        let answer = try await harness.call(
            "start agent", ["name": Self.agent, "agent": Self.otherAgent, "prompt": Self.prompt])

        #expect(answer == AgentsToolText.conflictingAgentNames(Self.agent, Self.otherAgent))
        #expect(await harness.runner.runs.isEmpty)
    }

    @Test("schedule agent takes name for its agent")
    func scheduleAgentTakesName() async throws {
        let harness = try await Self.harness()
        defer { try? harness.delete() }

        let answer = try await harness.call(
            "schedule agent", ["name": Self.agent, "schedule": "every 10 minutes", "prompt": Self.prompt])

        #expect(answer.contains("agent \(Self.agent)."), "\(answer)")
        #expect(await harness.runner.scheduledTasks(owner: nil).first?.agent == Self.agent)
    }

    @Test("schedule agent with a different name and agent is refused")
    func scheduleAgentConflict() async throws {
        let harness = try await Self.harness()
        defer { try? harness.delete() }

        let answer = try await harness.call(
            "schedule agent",
            ["name": Self.agent, "agent": Self.otherAgent, "schedule": "every 10 minutes", "prompt": Self.prompt])

        #expect(answer == AgentsToolText.conflictingAgentNames(Self.agent, Self.otherAgent))
        #expect(await harness.runner.scheduledTasks(owner: nil).isEmpty)
    }

    @Test("the description of a pending start agent call reads the agent key too")
    func callDescriptionReadsAgent() async throws {
        let harness = try await Self.harness()
        defer { try? harness.delete() }

        let description = harness.tool.callDescription(
            for: GeneratedContent(properties: ["op": "start agent", "agent": Self.agent, "prompt": Self.prompt]))

        #expect(description == AgentsToolText.callDescription(agent: Self.agent, prompt: Self.prompt))
    }

    @Test("a call with no op, an agent name and a prompt starts the agent")
    func noOpStartsTheAgent() async throws {
        let harness = try await Self.harness()
        defer { try? harness.delete() }

        let answer = try await harness.callWithNoOp(["name": Self.agent, "agent": Self.agent, "prompt": Self.prompt])

        #expect(answer.hasPrefix("Agent \(Self.agent) started with the id"), "\(answer)")
    }

    @Test("a call with no op, the agent key and a prompt starts the agent")
    func noOpWithAgentKeyStartsTheAgent() async throws {
        let harness = try await Self.harness()
        defer { try? harness.delete() }

        let answer = try await harness.callWithNoOp(["agent": Self.agent, "prompt": Self.prompt])

        #expect(answer.hasPrefix("Agent \(Self.agent) started with the id"), "\(answer)")
    }

    @Test("a call with no op and two different agents is refused, and starts no run")
    func noOpWithTwoAgentsIsRefused() async throws {
        let harness = try await Self.harness()
        defer { try? harness.delete() }

        let answer = try await harness.callWithNoOp(
            ["name": Self.agent, "agent": Self.otherAgent, "prompt": Self.prompt])

        #expect(answer == AgentsToolText.conflictingAgentNames(Self.agent, Self.otherAgent))
        #expect(await harness.runner.runs.isEmpty)
    }

    @Test("a call with no op whose fields do not fit start agent alone keeps the unknown-op corrective")
    func noOpThatFitsNoOneOpIsNotInferred() async throws {
        let payloads: [[String: String]] = [
            ["agent": Self.agent, "prompt": Self.prompt, "schedule": "every 10 minutes"],
            ["prompt": Self.prompt],
            ["name": Self.agent]
        ]
        for payload in payloads {
            let harness = try await Self.harness()
            defer { try? harness.delete() }

            let answer = try await harness.callWithNoOp(payload)

            #expect(answer.contains("Unknown operation"), "\(payload): \(answer)")
            #expect(await harness.runner.runs.isEmpty)
            #expect(await harness.runner.scheduledTasks(owner: nil).isEmpty)
        }
    }
}
