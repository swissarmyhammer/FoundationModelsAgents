import Foundation
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

@testable import FoundationModelsAgents

/// Pins the working folder of each run (D61).
///
/// The folder of a run is, in this order: the folder of the start request;
/// else the folder of the creator, the session that starts the run. For a
/// child run, the creator is the parent run. For a host session that is not
/// a run, and for the host API, the folder is
/// ``AgentEnvironment/workingDirectory``. An agent of the agent-folder source
/// never works in its own folder by default. A slash command gives the folder
/// of the session that runs it as the folder of the start request. A relative
/// folder of `start agent` starts from the folder of the creator. The session
/// of the run records the folder, and the `AGENTS.md` documents of the
/// instructions come from it.
///
/// Each folder of a test holds an `AGENTS.md` with a note of its own. Thus
/// the instructions of a run tell which folder the run read.
@Suite("Run working folder")
struct RunWorkingDirectoryTests {
    // MARK: - Constants

    /// The agent of the dotfolder layer with no `tools` key.
    private static let dotAgent = "dot-helper"

    /// The agent of the dotfolder layer that can start each agent.
    private static let leadAgent = "dot-lead"

    /// The agent of the agent-folder source.
    private static let folderAgent = AgentFolderFixture.helperID

    /// The name of the agent-instructions file of each folder.
    private static let agentsMdName = AgentRunHarness.agentsMdName

    /// The note of the `AGENTS.md` of the request folder.
    private static let requestNote = "Project note from the AGENTS.md of the request folder."

    /// The note of the `AGENTS.md` of the folder of the parent run.
    private static let parentNote = "Project note from the AGENTS.md of the parent folder."

    /// The note of the `AGENTS.md` of the folder of the agent-folder agent.
    private static let agentFolderNote = "Project note from the AGENTS.md of the agent folder."

    /// The note of the `AGENTS.md` of the environment folder.
    private static let environmentNote = AgentRunHarness.agentsMdText

    /// The prompt of each run that does the task. It is the key of its play.
    private static let prompt = "working-folder-key: do the task"

    /// The final text of each run that does the task.
    private static let finalText = "The task is done."

    /// The prompt of the lead run. It is the key of its play.
    private static let leadPrompt = "working-folder-lead-key: give the task to the helper"

    /// The name of the subfolder that a relative request folder names.
    private static let partFolderName = "part"

    /// The name of the field of `start agent` that holds the request folder.
    private static let folderField = "workingDirectory"

    /// The play of each run that does the task.
    private static let taskPlay = ScriptedAgentPlay(key: prompt, steps: [.finalText(finalText)])

    // MARK: - Fixture

    /// The folders and the harness of one test.
    private struct Fixture {
        /// The dotfolder layer that holds ``dotAgent`` and ``leadAgent``.
        let dotLayer: TemporaryLayer

        /// The agent-folder source that holds ``folderAgent``. The folder of
        /// the agent holds ``agentFolderNote``.
        let agentFolderSource: TemporaryLayer

        /// The folder that a start request names. It holds ``requestNote``.
        let requestFolder: TemporaryLayer

        /// The folder of the parent run of a child. It holds ``parentNote``.
        let parentFolder: TemporaryLayer

        /// The run harness. Its working directory is the environment folder.
        let harness: AgentRunHarness

        /// Removes each folder of the fixture.
        func delete() {
            try? harness.delete()
            for layer in [dotLayer, agentFolderSource, requestFolder, parentFolder] {
                try? layer.delete()
            }
        }
    }

    /// Makes the folders and a harness over a registry with the dotfolder
    /// layer and the agent-folder source.
    ///
    /// - Parameter plays: The plays of the script. The default is
    ///   ``taskPlay``.
    /// - Returns: The fixture. The test calls `delete()`.
    /// - Throws: The error of the file system or of the harness.
    private static func makeFixture(plays: [ScriptedAgentPlay] = [taskPlay]) async throws -> Fixture {
        let dotLayer = try TemporaryLayer.make(holding: [
            AgentDocumentPath.of(dotAgent): AgentFolderFixture.agentText(name: dotAgent),
            AgentDocumentPath.of(leadAgent): leadText
        ])
        let agentFolderSource = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: folderAgent): AgentFolderFixture.agentText(name: folderAgent),
            "\(folderAgent)/\(agentsMdName)": agentFolderNote
        ])
        let requestFolder = try TemporaryLayer.make(holding: [agentsMdName: requestNote])
        let parentFolder = try TemporaryLayer.make(holding: [
            agentsMdName: parentNote, "\(partFolderName)/\(agentsMdName)": requestNote
        ])
        let registry = AgentRegistry(layers: [dotLayer.layer], agentFolders: [agentFolderSource.root])
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript(plays), registry: registry)
        return Fixture(
            dotLayer: dotLayer, agentFolderSource: agentFolderSource, requestFolder: requestFolder,
            parentFolder: parentFolder, harness: harness)
    }

    /// The text of ``leadAgent``: an agent with an `Agent` entry.
    private static let leadText = """
        ---
        name: \(leadAgent)
        description: Gives a task to the helper.
        tools: Agent
        ---

        You are a lead.
        """

    // MARK: - Support

    /// Waits for the end of `run`, and gives the working folder that its
    /// session recorded.
    ///
    /// - Parameter run: A run that does the task.
    /// - Returns: The canonical path of the folder.
    /// - Throws: The error of the run, or of the read of the recording.
    private static func recordedFolder(of run: AgentRun) async throws -> String {
        #expect(try await run.result() == finalText)
        return try AgentRunTests.sidecar(of: run).workingDirectory.canonicalPath
    }

    /// Calls `start agent` of a tool whose session is a run in the parent
    /// folder of `fixture`, outside a Router session, and gives the child.
    ///
    /// - Parameters:
    ///   - agent: The agent of the child.
    ///   - folder: The `workingDirectory` field of the call, or `nil` for no
    ///     field.
    ///   - fixture: The folders and the harness.
    /// - Returns: The child run.
    /// - Throws: The error of ``startAgent(_:folder:from:in:)``.
    private static func startChild(
        _ agent: String, folder: String?, in fixture: Fixture
    ) async throws -> AgentRun {
        let parent = ParentRun(
            depth: AgentRunner.hostDepth, slot: .standard, agentID: leadAgent, family: ParentRun.Family(),
            workingDirectory: fixture.parentFolder.root)
        return try await startAgent(agent, folder: folder, from: parent, in: fixture)
    }

    /// Calls `start agent` of a tool whose session is `parent`, outside a
    /// Router session, and gives the new run.
    ///
    /// - Parameters:
    ///   - agent: The agent of the new run.
    ///   - folder: The `workingDirectory` field of the call, or `nil` for no
    ///     field.
    ///   - parent: The run whose session holds the tool, or `nil` for a host
    ///     session that is not a run.
    ///   - fixture: The folders and the harness.
    /// - Returns: The new run.
    /// - Throws: The error of the tool, or of `#require` when the call
    ///   started no run.
    private static func startAgent(
        _ agent: String, folder: String?, from parent: ParentRun?, in fixture: Fixture
    ) async throws -> AgentRun {
        let runner = fixture.harness.makeRunner()
        let tool = try await AgentsTool.make(
            context: AgentsToolContext(runner: runner, allowedNames: nil, parent: parent, callerLink: nil, grant: .full))
        let toolHarness = AgentsToolHarness(runHarness: fixture.harness, runner: runner, tool: tool)
        var fields = ["name": agent, "prompt": prompt]
        fields[folderField] = folder
        let answer = try await toolHarness.call("start agent", fields)
        let runs = await runner.runs(caller: nil)
        #expect(runs.count == 1)
        let child = try #require(runs.first)
        #expect(answer == AgentsToolText.started(child))
        return child
    }

    /// Runs the slash command of `agent` from a session whose folder is the
    /// request folder of `fixture`, and gives the run of the command.
    ///
    /// - Parameters:
    ///   - agent: The agent of the command.
    ///   - fixture: The folders and the harness.
    /// - Returns: The run of the command.
    /// - Throws: The error of the command, or of `#require` when the agent
    ///   has no `.action` command or the command started no run.
    private static func runCommand(of agent: String, in fixture: Fixture) async throws -> AgentRun {
        let runner = fixture.harness.makeRunner()
        let sessionFolder = fixture.requestFolder.root
        let commands = await runner.commands(workingDirectory: sessionFolder)
        let command = try #require(commands.first { $0.name == agent })
        let action = try #require(SlashCommandTests.action(of: command))
        let texts: [String] = try await action(
            SlashCommand.Invocation(arguments: prompt, workingDirectory: sessionFolder)
        ).reduce(into: []) { texts, text in texts.append(text) }
        #expect(texts == [finalText])
        let runs = await runner.runs(caller: nil)
        #expect(runs.count == 1)
        return try #require(runs.first)
    }

    // MARK: - Host-started runs

    @Test("a host run with its own folder works in that folder and reads its AGENTS.md")
    func hostRunWithItsOwnFolder() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }
        let runner = fixture.harness.makeRunner()

        let run = try await runner.start(Self.dotAgent, prompt: Self.prompt, workingDirectory: fixture.requestFolder.root)

        #expect(try await Self.recordedFolder(of: run) == fixture.requestFolder.root.canonicalPath)
        let instructions = try AgentRunTests.instructions(of: run)
        #expect(instructions.contains(Self.requestNote))
        #expect(!instructions.contains(Self.environmentNote))
    }

    @Test("a root run of an agent-folder agent with no folder works in the environment folder, not in the agent folder")
    func rootRunOfAgentFolderAgentUsesEnvironmentFolder() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }
        let runner = fixture.harness.makeRunner()

        let run = try await runner.start(Self.folderAgent, prompt: Self.prompt)

        #expect(try await Self.recordedFolder(of: run) == fixture.harness.workingDirectory.canonicalPath)
        let instructions = try AgentRunTests.instructions(of: run)
        #expect(instructions.contains(Self.environmentNote))
        #expect(!instructions.contains(Self.agentFolderNote))
    }

    @Test("a root run of a dotfolder agent with no folder works in the environment folder")
    func rootRunOfDotfolderAgentUsesEnvironmentFolder() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }
        let runner = fixture.harness.makeRunner()

        let run = try await runner.start(Self.dotAgent, prompt: Self.prompt)

        #expect(try await Self.recordedFolder(of: run) == fixture.harness.workingDirectory.canonicalPath)
        #expect(try AgentRunTests.instructions(of: run).contains(Self.environmentNote))
    }

    @Test("a host run of an agent-folder agent with a request folder works in that folder, not in the agent folder")
    func requestFolderOfAgentFolderAgentIsItsFolder() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }
        let runner = fixture.harness.makeRunner()

        let run = try await runner.start(
            Self.folderAgent, prompt: Self.prompt, workingDirectory: fixture.requestFolder.root)

        #expect(try await Self.recordedFolder(of: run) == fixture.requestFolder.root.canonicalPath)
        let instructions = try AgentRunTests.instructions(of: run)
        #expect(instructions.contains(Self.requestNote))
        #expect(!instructions.contains(Self.agentFolderNote))
    }

    // MARK: - Runs that a host session starts

    @Test("a start agent call from a host session that is not a run works in the environment folder, not in the agent folder")
    func startFromHostSessionUsesEnvironmentFolder() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }

        let run = try await Self.startAgent(Self.folderAgent, folder: nil, from: nil, in: fixture)

        #expect(try await Self.recordedFolder(of: run) == fixture.harness.workingDirectory.canonicalPath)
        let instructions = try AgentRunTests.instructions(of: run)
        #expect(instructions.contains(Self.environmentNote))
        #expect(!instructions.contains(Self.agentFolderNote))
    }

    @Test("a relative folder of a start agent call from a host session starts from the environment folder")
    func relativeRequestFolderOfHostSessionStartsFromEnvironmentFolder() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }
        try fixture.harness.scratch.write(Self.requestNote, at: "\(Self.partFolderName)/\(Self.agentsMdName)")

        let run = try await Self.startAgent(Self.folderAgent, folder: Self.partFolderName, from: nil, in: fixture)

        let part = fixture.harness.workingDirectory.appendingPathComponent(Self.partFolderName, isDirectory: true)
        #expect(try await Self.recordedFolder(of: run) == part.canonicalPath)
        #expect(try AgentRunTests.instructions(of: run).contains(Self.requestNote))
    }

    // MARK: - Slash-command runs

    @Test("a command run of a dotfolder agent works in the folder of the session")
    func commandRunOfDotfolderAgentUsesSessionFolder() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }

        let run = try await Self.runCommand(of: Self.dotAgent, in: fixture)

        #expect(try await Self.recordedFolder(of: run) == fixture.requestFolder.root.canonicalPath)
        let instructions = try AgentRunTests.instructions(of: run)
        #expect(instructions.contains(Self.requestNote))
        #expect(!instructions.contains(Self.environmentNote))
    }

    @Test("a command run of an agent-folder agent works in the folder of the session, not in the agent folder")
    func commandRunOfAgentFolderAgentUsesSessionFolder() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }

        let run = try await Self.runCommand(of: Self.folderAgent, in: fixture)

        #expect(try await Self.recordedFolder(of: run) == fixture.requestFolder.root.canonicalPath)
        let instructions = try AgentRunTests.instructions(of: run)
        #expect(instructions.contains(Self.requestNote))
        #expect(!instructions.contains(Self.agentFolderNote))
    }

    // MARK: - Child runs

    @Test("a child of a dotfolder agent works in the folder of its parent")
    func childOfDotfolderAgentUsesFolderOfParent() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }

        let child = try await Self.startChild(Self.dotAgent, folder: nil, in: fixture)

        #expect(try await Self.recordedFolder(of: child) == fixture.parentFolder.root.canonicalPath)
        #expect(try AgentRunTests.instructions(of: child).contains(Self.parentNote))
    }

    @Test("a child of an agent-folder agent works in the folder of its parent, not in the agent folder")
    func childOfAgentFolderAgentUsesFolderOfParent() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }

        let child = try await Self.startChild(Self.folderAgent, folder: nil, in: fixture)

        #expect(try await Self.recordedFolder(of: child) == fixture.parentFolder.root.canonicalPath)
        let instructions = try AgentRunTests.instructions(of: child)
        #expect(instructions.contains(Self.parentNote))
        #expect(!instructions.contains(Self.agentFolderNote))
    }

    @Test("the folder of a start agent call wins over the parent folder, also for an agent-folder agent")
    func requestFolderOfStartAgentWinsOverAll() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }

        let child = try await Self.startChild(
            Self.folderAgent, folder: fixture.requestFolder.root.path, in: fixture)

        #expect(try await Self.recordedFolder(of: child) == fixture.requestFolder.root.canonicalPath)
        let instructions = try AgentRunTests.instructions(of: child)
        #expect(instructions.contains(Self.requestNote))
        #expect(!instructions.contains(Self.parentNote))
        #expect(!instructions.contains(Self.agentFolderNote))
    }

    @Test("a relative folder of a start agent call starts from the folder of the parent")
    func relativeRequestFolderStartsFromParentFolder() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }

        let child = try await Self.startChild(Self.dotAgent, folder: Self.partFolderName, in: fixture)

        let part = fixture.parentFolder.root.appendingPathComponent(Self.partFolderName, isDirectory: true)
        #expect(try await Self.recordedFolder(of: child) == part.canonicalPath)
        #expect(try AgentRunTests.instructions(of: child).contains(Self.requestNote))
    }

    @Test("a blank folder of a start agent call names no folder")
    func blankRequestFolderNamesNoFolder() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }

        let child = try await Self.startChild(Self.dotAgent, folder: "  ", in: fixture)

        #expect(try await Self.recordedFolder(of: child) == fixture.parentFolder.root.canonicalPath)
    }

    @Test("a child that a run starts works in the folder of that run, also for an agent-folder agent")
    func childOfRunUsesFolderOfThatRun() async throws {
        let fixture = try await Self.makeFixture(plays: [
            NestedRunTests.parentPlay(Self.leadPrompt, children: [(Self.folderAgent, Self.prompt)]),
            Self.taskPlay
        ])
        defer { fixture.delete() }
        let runner = fixture.harness.makeRunner()

        let lead = try await runner.start(
            Self.leadAgent, prompt: Self.leadPrompt, workingDirectory: fixture.requestFolder.root)
        _ = try await lead.result()
        let child = try await NestedRunTests.onlyRun(of: runner, caller: lead.id)

        #expect(try await Self.recordedFolder(of: child) == fixture.requestFolder.root.canonicalPath)
        #expect(try AgentRunTests.instructions(of: child).contains(Self.requestNote))
    }
}
