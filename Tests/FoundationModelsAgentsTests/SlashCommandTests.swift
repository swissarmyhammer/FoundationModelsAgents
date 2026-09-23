import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the slash commands of `AgentRunner` (plan.md §9.4): one command for
/// each user-invocable agent, an `.action` body that delegates the typed text
/// to a host-driven run, `commandUpdates` after a reload, the command names of
/// `AgentReloadReport`, and no `agent:` key in a fixture skill.
@Suite("Slash commands")
struct SlashCommandTests {
    /// The action of an `.action` body.
    typealias Action = @Sendable (SlashCommand.Invocation) -> AsyncThrowingStream<String, Error>

    /// The agent of the fixture library that the command starts.
    private static let reviewer = AgentRunTests.reviewer

    /// The agent of the fixture library that has `user-invocable: false`.
    private static let hiddenAgent = "internal-helper"

    /// The text after the name of the command. It is also the key of the
    /// play.
    private static let task = "check the diff"

    /// The final text of the play.
    private static let finalText = "The diff has no defects."

    /// The argument hint of each command.
    private static let taskHint = "<task>"

    /// The id of the agent that the reload row adds.
    private static let addedAgent = "added-agent"

    /// The path of the file of `addedAgent`, relative to the layer root.
    private static let addedAgentPath = "agents/\(addedAgent).md"

    /// The description of the agent that the reload row adds.
    private static let addedDescription = "An agent that a reload adds."

    /// The text of the file of the agent that the reload row adds.
    private static let addedAgentText = """
        ---
        name: \(addedAgent)
        description: \(addedDescription)
        ---

        You are an agent of a test.
        """

    /// The key of the frontmatter that no fixture skill may hold.
    private static let agentKeyPrefix = "agent:"

    /// The file name of a skill.
    private static let skillFileName = "SKILL.md"

    /// The line that opens and closes a frontmatter.
    private static let frontmatterFence = "---"

    @Test("/code-reviewer check the diff starts code-reviewer with the prompt and gives its final text")
    func commandStartsTheAgentAndGivesItsFinalText() async throws {
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([ScriptedAgentPlay(key: Self.task, steps: [.finalText(Self.finalText)])]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()
        let commands = await runner.commands(workingDirectory: harness.workingDirectory)
        let command = try #require(commands.first { $0.name == Self.reviewer })
        let action = try #require(Self.action(of: command))

        let texts: [String] = try await action(
            SlashCommand.Invocation(arguments: Self.task, workingDirectory: harness.workingDirectory)
        ).reduce(into: []) { texts, text in texts.append(text) }

        #expect(texts == [Self.finalText])
        #expect(harness.script.prompts == [Self.task])
        #expect(command.argumentHint == Self.taskHint)
        #expect(command.description == harness.registry.catalog().definition(named: Self.reviewer)?.description)
        let run = try #require(await runner.runs(caller: nil).first)
        #expect(run.agent.id == Self.reviewer)
        #expect(run.state == .finished(Self.finalText))
    }

    @Test("a cancel of the command stream cancels the run", .timeLimit(.minutes(1)))
    func cancelOfTheStreamCancelsTheRun() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(key: Self.task, steps: [.wait(gate), .finalText(Self.finalText)])
            ]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()
        let commands = await runner.commands(workingDirectory: harness.workingDirectory)
        let command = try #require(commands.first { $0.name == Self.reviewer })
        let action = try #require(Self.action(of: command))
        let invocation = SlashCommand.Invocation(arguments: Self.task, workingDirectory: harness.workingDirectory)
        let reader = Task { () async throws -> [String] in
            try await action(invocation).reduce(into: []) { texts, text in texts.append(text) }
        }

        await gate.waitForArrival()
        reader.cancel()
        let texts = try await reader.value
        let run = try #require(await runner.runs(caller: nil).first)

        #expect(texts.isEmpty)
        #expect(await run.finalState() == .cancelled)
    }

    @Test("each user-invocable agent has one command, and a user-invocable: false agent has none")
    func onlyUserInvocableAgentsHaveCommands() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let names = await runner.commands(workingDirectory: harness.workingDirectory).map(\.name)

        #expect(names == FixtureLibrary.localAgentIDs.subtracting([Self.hiddenAgent]).sorted())
        #expect(!names.contains(Self.hiddenAgent))
    }

    @Test("commandUpdates yields the new command list after an agent reload", .timeLimit(.minutes(1)))
    func commandUpdatesYieldAfterAReload() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([]), registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()
        let updates = try #require(runner.commandUpdates)

        try layer.write(Self.addedAgentText, at: Self.addedAgentPath)
        try await harness.registry.reload()

        let commands = try #require(await updates.first { _ in true })
        #expect(commands.map(\.name) == [Self.addedAgent])
        #expect(commands.map(\.description) == [Self.addedDescription])
    }

    @Test("AgentReloadReport lists the slash-command names")
    func reloadReportListsTheCommandNames() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let report = AgentReloadReport(catalog: harness.registry.catalog(), marketplaceLayers: [])

        let names = await runner.commands(workingDirectory: harness.workingDirectory).map(\.name)
        #expect(report.slashCommandNames == names)
        #expect(!report.slashCommandNames.contains(Self.hiddenAgent))
    }

    @Test("no fixture skill has an agent: key")
    func noFixtureSkillHasAnAgentKey() throws {
        let skills = try Self.skillFiles(under: FixtureLibrary.root)

        #expect(!skills.isEmpty)
        for skill in skills {
            let frontmatter = try Self.frontmatterLines(of: skill)
            #expect(!frontmatter.contains { $0.hasPrefix(Self.agentKeyPrefix) }, "\(skill.path)")
        }
    }

    /// Gives the action of the body of `command`.
    ///
    /// - Parameter command: The command.
    /// - Returns: The action, or `nil` when the body is not `.action`.
    private static func action(of command: SlashCommand) -> Action? {
        switch command.body {
        case .action(let action):
            action
        case .prompt, .rendered:
            nil
        }
    }

    /// Finds each `SKILL.md` file under `root`.
    ///
    /// - Parameter root: The folder to search.
    /// - Returns: The URL of each skill file.
    /// - Throws: An error when the folder cannot be read.
    private static func skillFiles(under root: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return Array(enumerator.lazy.compactMap { $0 as? URL }.filter { $0.lastPathComponent == skillFileName })
    }

    /// Gives the lines of the frontmatter of `file`: the lines between the
    /// first two fences.
    ///
    /// - Parameter file: The skill file.
    /// - Returns: The frontmatter lines.
    /// - Throws: An error when the file cannot be read as UTF-8 text.
    private static func frontmatterLines(of file: URL) throws -> [String] {
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
        return Array(lines.dropFirst().prefix { $0 != frontmatterFence })
    }
}
