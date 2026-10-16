import Foundation
import FoundationModelsRouter
import Testing

@testable import FoundationModelsAgents

/// Pins the working folder of each run (D61).
///
/// The folder of a run is, in this order: the folder of the start request;
/// for a child run, the folder of the parent run; only for an agent of the
/// agent-folder source, the folder of the agent; else
/// ``AgentEnvironment/workingDirectory``. The session of the run records the
/// folder, and the `AGENTS.md` documents of the instructions come from it.
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

        /// The agent-folder source that holds ``folderAgent``.
        let agentFolderSource: TemporaryLayer

        /// The folder that a start request names. It holds ``requestNote``.
        let requestFolder: TemporaryLayer

        /// The folder of the parent run of a child. It holds ``parentNote``.
        let parentFolder: TemporaryLayer

        /// The run harness. Its working directory is the environment folder.
        let harness: AgentRunHarness

        /// The folder of ``folderAgent``. It holds ``agentFolderNote``.
        var agentFolder: URL {
            agentFolderSource.root.appendingPathComponent(folderAgent, isDirectory: true)
        }

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
    /// - Throws: The error of the tool, or of `#require` when the call
    ///   started no run.
    private static func startChild(
        _ agent: String, folder: String?, in fixture: Fixture
    ) async throws -> AgentRun {
        let runner = fixture.harness.makeRunner()
        let parent = ParentRun(
            depth: AgentRunner.hostDepth, slot: .standard, agentID: leadAgent, family: ParentRun.Family(),
            workingDirectory: fixture.parentFolder.root)
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

    @Test("a root run of an agent-folder agent with no folder works in the folder of the agent")
    func rootRunOfAgentFolderAgentUsesItsFolder() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.delete() }
        let runner = fixture.harness.makeRunner()

        let run = try await runner.start(Self.folderAgent, prompt: Self.prompt)

        #expect(try await Self.recordedFolder(of: run) == fixture.agentFolder.canonicalPath)
        let instructions = try AgentRunTests.instructions(of: run)
        #expect(instructions.contains(Self.agentFolderNote))
        #expect(!instructions.contains(Self.environmentNote))
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

    @Test("a request folder wins over the folder of an agent-folder agent")
    func requestFolderWinsOverAgentFolder() async throws {
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

    @Test("the folder of a start agent call wins over the parent folder and the agent folder")
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
