@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins a reload while runs and tools are in use (plan.md §6.1, §9.1, §15).
///
/// A run keeps the definition that it started with. An `agents` tool that
/// was made before a reload reads the current catalog in each call, but its
/// schema stays as it was made. Each row works on a `TemporaryLayer` and
/// plays the scripted profile. The agents run on the `flash` slot.
@Suite("Reload during a run")
struct ReloadDuringRunTests {
    /// The agent whose file a row changes.
    private static let changedAgent = "changed-agent"

    /// The agent whose file a row removes.
    private static let removedAgent = "removed-agent"

    /// The agent whose file a row adds after the tool is made.
    private static let addedAgent = "added-agent"

    /// The description of each agent file before the change.
    private static let firstDescription = "Checks the first version of the text."

    /// The description of the changed agent file.
    private static let secondDescription = "Checks the second version of the text."

    /// The body of each agent file before the change.
    private static let firstBody = "You check the first version of the text that the prompt names."

    /// The body of the changed agent file.
    private static let secondBody = "You check the second version of the text that the prompt names."

    /// The prompt of each run. It is also the key of the play of the run.
    private static let prompt = "reload-during-run-key: check the text"

    /// The final text of the play of a run.
    private static let finalText = "The text is correct."

    /// A script with one play for ``prompt``.
    ///
    /// - Parameter steps: The steps of the play.
    /// - Returns: The script.
    private static func script(_ steps: [ScriptedAgentStep]) -> ScriptedAgentScript {
        ScriptedAgentScript([ScriptedAgentPlay(key: prompt, steps: steps)])
    }

    /// The text of an agent file on the `flash` slot.
    ///
    /// - Parameters:
    ///   - name: The id of the agent.
    ///   - description: The description of the agent.
    ///   - body: The body of the agent.
    /// - Returns: The file text.
    private static func agentFile(_ name: String, description: String, body: String) -> String {
        """
        ---
        name: \(name)
        description: \(description)
        model: flash
        ---
        \(body)
        """
    }

    /// Writes the first version of the file of each agent into `layer`.
    ///
    /// - Parameters:
    ///   - agents: The ids of the agents.
    ///   - layer: The layer.
    /// - Throws: The error of the file system.
    private static func writeFirstVersions(of agents: [String], in layer: TemporaryLayer) throws {
        for agent in agents {
            try layer.write(agentFile(agent, description: firstDescription, body: firstBody), at: agentPath(agent))
        }
    }

    /// Writes the second version of the file of `agent` into `layer`.
    ///
    /// - Parameters:
    ///   - agent: The id of the agent.
    ///   - layer: The layer.
    /// - Throws: The error of the file system.
    private static func writeSecondVersion(of agent: String, in layer: TemporaryLayer) throws {
        try layer.write(agentFile(agent, description: secondDescription, body: secondBody), at: agentPath(agent))
    }

    /// The path of the file of the agent `name` in a layer.
    ///
    /// - Parameter name: The id of the agent.
    /// - Returns: The relative path.
    private static func agentPath(_ name: String) -> String {
        "agents/\(name).md"
    }

    /// The fields of a `start agent` payload for ``prompt``.
    ///
    /// - Parameter name: The name of the agent.
    /// - Returns: The fields.
    private static func startFields(_ name: String) -> [String: String] {
        ["name": name, "prompt": prompt]
    }

    @Test("a run in operation keeps its definition after the file changes and the registry reloads",
        .timeLimit(.minutes(1)))
    func runInOperationKeepsItsDefinition() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.writeFirstVersions(of: [Self.changedAgent], in: layer)
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: Self.script([.wait(gate), .finalText(Self.finalText)]),
            registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }

        let run = try await harness.start(Self.changedAgent, prompt: Self.prompt)
        await gate.waitForArrival()
        try Self.writeSecondVersion(of: Self.changedAgent, in: layer)
        try await harness.registry.reload()
        let current = try #require(harness.registry.catalog().definition(named: Self.changedAgent))
        gate.open()
        let result = try await run.result()
        let instructions = try #require(try AgentRunTests.sidecar(of: run).configuration.instructions)

        #expect(current.description == Self.secondDescription)
        #expect(run.agent.description == Self.firstDescription)
        #expect(run.agent.body.contains(Self.firstBody))
        #expect(instructions.contains(Self.firstBody))
        #expect(!instructions.contains(Self.secondBody))
        #expect(result == Self.finalText)
    }

    @Test("a tool made before a reload runs a changed agent with the new definition")
    func toolMadeBeforeReloadRunsTheChangedAgent() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.writeFirstVersions(of: [Self.changedAgent], in: layer)
        let harness = try await AgentsToolHarness.make(
            script: Self.script([.finalText(Self.finalText)]), registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }

        try Self.writeSecondVersion(of: Self.changedAgent, in: layer)
        try await harness.runHarness.registry.reload()
        _ = try await harness.call("start agent", Self.startFields(Self.changedAgent))
        let run = try #require(await harness.runner.runs(caller: nil).first)
        let result = try await run.result()
        let instructions = try #require(try AgentRunTests.sidecar(of: run).configuration.instructions)

        #expect(run.agent.description == Self.secondDescription)
        #expect(instructions.contains(Self.secondBody))
        #expect(result == Self.finalText)
    }

    @Test("a tool made before a reload gives the corrective with the current names for a removed agent")
    func toolMadeBeforeReloadCorrectsARemovedAgent() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.writeFirstVersions(of: [Self.changedAgent, Self.removedAgent], in: layer)
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }

        try layer.remove(Self.agentPath(Self.removedAgent))
        try await harness.runHarness.registry.reload()
        let answer = try await harness.call("start agent", Self.startFields(Self.removedAgent))

        #expect(harness.tool.agentNames == [Self.changedAgent, Self.removedAgent])
        #expect(answer == AgentsToolText.unknownAgent(Self.removedAgent, available: [Self.changedAgent]))
        #expect(await harness.runner.runs.isEmpty)
    }

    @Test("a tool made before a reload lists an added agent, and its schema does not hold the agent")
    func toolMadeBeforeReloadListsAnAddedAgent() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.writeFirstVersions(of: [Self.changedAgent], in: layer)
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }

        try Self.writeFirstVersions(of: [Self.addedAgent], in: layer)
        try await harness.runHarness.registry.reload()
        let listed = try await harness.call("list agents")
        let nameProperty = try AgentsToolSchemaTests.property(
            named: AgentsToolSchemaTests.nameFieldName, in: harness.tool.parameters)
        let nextTool = try await AgentsTool.make(context: AgentsToolContext(runner: harness.runner))

        #expect(listed.contains("- \(Self.addedAgent): \(Self.firstDescription)"))
        #expect(harness.tool.agentNames == [Self.changedAgent])
        #expect(nameProperty["enum"] as? [String] == [Self.changedAgent])
        #expect(nextTool.agentNames == [Self.addedAgent, Self.changedAgent])
    }
}
