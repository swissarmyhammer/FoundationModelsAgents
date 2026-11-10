import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the write operations of the `agents` tool (AG-9): `add agent`,
/// `edit agent` and `remove agent`, with the `layer` option.
///
/// Each test calls the tool outside a Router session over a `user < project`
/// stack in temporary folders. The registry does not watch its layers, thus
/// only the reload of the operation changes the catalog. A test of the
/// change events reads the change log of the registry through the `agents`
/// endpoint, as ``AgentsGraphChangesTests`` does.
@Suite("Agents tool write operations")
struct AgentsToolWriteTests {
    // MARK: - Constants

    /// The id of the agent that most tests write.
    private static let id = "reviewer"

    /// The description of the agent that a test writes.
    private static let newDescription = "Reviews a diff for the write tests."

    /// The text of a valid `AGENT.md` of ``id``.
    private static let agentText = AgentFolderFixture.agentText(name: id, description: newDescription)

    /// The text of an `AGENT.md` of ``id`` with no `description` key: the
    /// agent loads with a warning.
    private static let noDescriptionText = """
        ---
        name: \(id)
        ---

        \(AgentFolderFixture.body)
        """

    /// The text of an `AGENT.md` with no frontmatter: the agent does not
    /// load.
    private static let noFrontmatterText = "No frontmatter here."

    /// The text of a resource document of an agent.
    private static let notesText = "Notes of the agent."

    /// The path of a resource document, relative to the agent folder.
    private static let notesDocument = "notes.md"

    /// The body of the default agent after an edit.
    private static let editedDefaultBody = "You are the edited default agent."

    /// The prompt of the run that a test starts. It is also the key of its
    /// play.
    private static let prompt = "write-tests-run-key: review the diff"

    /// The final text of the run that a test starts.
    private static let finalText = "The diff is correct."

    /// The text between two parts of an answer.
    private static let partSeparator = "\n\n"

    /// The answer part of a write that does not change the catalog.
    private static let unchangedText = "The catalog did not change."

    /// The corrective of a `layer` value that is not a layer.
    private static let badLayerText = "The layer `global` is not valid. Give `user` or `project`, or leave it out for `user`."

    /// A `layer` value that is not a layer.
    private static let badLayer = "global"

    /// Each verb alias of a write operation, with the first word of the
    /// answer of the operation that it names.
    private static let verbAliases: [(op: String, action: String)] = [
        ("delete agent", "Removed"),
        ("rm agent", "Removed"),
        ("del agent", "Removed"),
        ("create agent", "Added"),
        ("new agent", "Added"),
        ("update agent", "Edited"),
        ("change agent", "Edited")
    ]

    // MARK: - add agent

    @Test("add agent writes <user root>/<id>/AGENT.md, and the catalog holds the agent from the user layer")
    func addWritesTheUserLayer() async throws {
        let fixture = try await WriteFixture.make()
        defer { fixture.delete() }

        _ = try await fixture.call("add agent", ["name": Self.id, "content": Self.agentText])

        #expect(try fixture.user.text(at: AgentFolderFixture.documentPath(of: Self.id)) == Self.agentText)
        #expect(fixture.registry.catalog().definition(named: Self.id)?.layer.source == .user)
    }

    @Test("add agent with the layer project writes <project root>/<id>/AGENT.md")
    func addWritesTheProjectLayer() async throws {
        let fixture = try await WriteFixture.make()
        defer { fixture.delete() }

        _ = try await fixture.call("add agent", ["name": Self.id, "content": Self.agentText, "layer": "project"])

        #expect(try fixture.project.text(at: AgentFolderFixture.documentPath(of: Self.id)) == Self.agentText)
        #expect(fixture.registry.catalog().definition(named: Self.id)?.layer.source == .project)
    }

    @Test("the answer of add agent names the file and the layer, then the diagnostics of the agent")
    func addAnswerNamesTheFileTheLayerAndTheDiagnostics() async throws {
        let fixture = try await WriteFixture.make()
        defer { fixture.delete() }
        let path = fixture.user.root.appendingPathComponent(AgentFolderFixture.documentPath(of: Self.id)).path

        let answer = try await fixture.call("add agent", ["name": Self.id, "content": Self.agentText])

        #expect(
            answer == "Added the agent `\(Self.id)` to the user layer: `\(path)`." + Self.partSeparator
                + "The agent `\(Self.id)` is in the catalog with no diagnostics.")
    }

    @Test("start agent starts an agent that add agent wrote in the same session")
    func addThenStartStartsTheAgent() async throws {
        let fixture = try await WriteFixture.make(
            script: ScriptedAgentScript([ScriptedAgentPlay(key: Self.prompt, steps: [.finalText(Self.finalText)])]))
        defer { fixture.delete() }

        _ = try await fixture.call("add agent", ["name": Self.id, "content": Self.agentText])
        let answer = try await fixture.call("start agent", ["name": Self.id, "prompt": Self.prompt])
        let run = try #require(await fixture.harness.runner.runs(caller: nil).first)
        _ = try await run.result()

        #expect(answer == AgentsToolText.started(run))
    }

    @Test("add agent of a file with a frontmatter warning gives the diagnostics of the new catalog for the id")
    func addWithAWarningGivesTheDiagnostics() async throws {
        let fixture = try await WriteFixture.make()
        defer { fixture.delete() }

        let answer = try await fixture.call("add agent", ["name": Self.id, "content": Self.noDescriptionText])
        let diagnostic = try #require(
            fixture.registry.catalog().diagnostics.first { $0.agent == Self.id && $0.code == .missingDescription })

        #expect(answer.hasSuffix("- warning \(diagnostic.code.rawValue): \(diagnostic.message)"))
    }

    @Test("add agent of a file with no frontmatter says that the agent is not in the catalog, and why")
    func addWithNoFrontmatterReportsTheSkip() async throws {
        let fixture = try await WriteFixture.make()
        defer { fixture.delete() }

        let answer = try await fixture.call("add agent", ["name": Self.id, "content": Self.noFrontmatterText])
        let skip = try #require(fixture.registry.catalog().diagnostics.first { $0.agent == Self.id })

        #expect(
            answer.hasSuffix(
                "The agent `\(Self.id)` is not in the catalog. Correct the file with 'edit agent':\n"
                    + "- skip \(skip.code.rawValue): \(skip.message)"))
    }

    @Test("add agent takes agent as an alias of name")
    func addTakesTheAgentAlias() async throws {
        let fixture = try await WriteFixture.make()
        defer { fixture.delete() }

        _ = try await fixture.call("add agent", ["agent": Self.id, "content": Self.agentText])

        #expect(fixture.registry.catalog().definition(named: Self.id) != nil)
    }

    @Test("add agent with a name and an agent that differ gives the conflict corrective, and writes no file")
    func addWithConflictingNamesGivesTheCorrective() async throws {
        let fixture = try await WriteFixture.make()
        defer { fixture.delete() }
        let before = try fixture.snapshot()

        let answer = try await fixture.call(
            "add agent", ["name": Self.id, "agent": AgentFolderFixture.helperID, "content": Self.agentText])

        #expect(answer == AgentsToolText.conflictingAgentNames(Self.id, AgentFolderFixture.helperID))
        #expect(try fixture.snapshot() == before)
    }

    // MARK: - edit agent

    @Test("edit agent of default changes the root AGENT.md of the user layer, and the runner gives the new instructions")
    func editDefaultChangesTheDefaultInstructions() async throws {
        let fixture = try await WriteFixture.make(user: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName)
        ])
        defer { fixture.delete() }

        _ = try await fixture.call(
            "edit agent",
            [
                "name": AgentCatalog.defaultAgentID,
                "content": AgentFolderFixture.agentText(
                    name: AgentFolderFixture.displayName, body: Self.editedDefaultBody)
            ])
        let instructions = try #require(try await fixture.harness.runner.defaultAgentInstructions())

        #expect(instructions.body.contains(Self.editedDefaultBody))
    }

    @Test("edit agent of a resource document writes it, and says that the catalog did not change")
    func editOfAResourceDocumentSaysTheCatalogDidNotChange() async throws {
        let fixture = try await WriteFixture.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.agentText])
        defer { fixture.delete() }

        let answer = try await fixture.call(
            "edit agent", ["name": Self.id, "document": Self.notesDocument, "content": Self.notesText])

        #expect(try fixture.user.text(at: "\(Self.id)/\(Self.notesDocument)") == Self.notesText)
        #expect(answer.hasSuffix(Self.partSeparator + Self.unchangedText))
    }

    @Test("edit agent with the same text says that the catalog did not change")
    func editWithTheSameTextSaysTheCatalogDidNotChange() async throws {
        let fixture = try await WriteFixture.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.agentText])
        defer { fixture.delete() }

        let answer = try await fixture.call("edit agent", ["name": Self.id, "content": Self.agentText])

        #expect(answer.hasSuffix(Self.partSeparator + Self.unchangedText))
    }

    @Test("edit agent of a copy that a higher layer hides names the layer that wins")
    func editOfAHiddenCopyNamesTheWinningLayer() async throws {
        let fixture = try await WriteFixture.make(
            user: [AgentFolderFixture.documentPath(of: Self.id): Self.agentText],
            project: [AgentFolderFixture.documentPath(of: Self.id): Self.agentText])
        defer { fixture.delete() }

        let answer = try await fixture.call("edit agent", ["name": Self.id, "content": Self.noDescriptionText])

        #expect(answer.hasSuffix("The catalog did not change: the copy in the project layer wins."))
    }

    // MARK: - remove agent

    @Test("remove agent deletes the agent folder, and the catalog does not hold the agent")
    func removeDeletesTheAgent() async throws {
        let fixture = try await WriteFixture.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.agentText])
        defer { fixture.delete() }

        _ = try await fixture.call("remove agent", ["name": Self.id])

        #expect(!FileManager.default.fileExists(atPath: fixture.user.root.appendingPathComponent(Self.id).path))
        #expect(fixture.registry.catalog().definition(named: Self.id) == nil)
    }

    @Test("the answer of remove agent names the folder and the layer")
    func removeAnswerNamesTheFolderAndTheLayer() async throws {
        let fixture = try await WriteFixture.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.agentText])
        defer { fixture.delete() }
        let folder = fixture.user.root.appendingPathComponent(Self.id, isDirectory: true).path

        let answer = try await fixture.call("remove agent", ["name": Self.id])

        #expect(answer.hasPrefix("Removed the agent `\(Self.id)` from the user layer: `\(folder)"))
    }

    // MARK: - Correctives

    @Test("a layer that is not user or project gives a corrective that names the two layers, and changes no file")
    func aBadLayerGivesACorrective() async throws {
        let fixture = try await WriteFixture.make()
        defer { fixture.delete() }
        let before = try fixture.snapshot()

        let answer = try await fixture.call(
            "add agent", ["name": Self.id, "content": Self.agentText, "layer": Self.badLayer])

        #expect(answer == Self.badLayerText)
        #expect(try fixture.snapshot() == before)
    }

    @Test(
        "a bad id, a reserved id and a missing agent give the corrective of the writer, and change no file",
        arguments: [
            ("add agent", "Bad_ID", AgentWriterError.invalidID("Bad_ID")),
            ("add agent", "skills", AgentWriterError.reservedID("skills")),
            ("remove agent", "reviewer", AgentWriterError.notFound(id: "reviewer", layer: .user, existsIn: [])),
            ("edit agent", "reviewer", AgentWriterError.notFound(id: "reviewer", layer: .user, existsIn: []))
        ])
    func aRefusedWriteGivesTheCorrectiveOfTheWriter(op: String, name: String, error: AgentWriterError) async throws {
        let fixture = try await WriteFixture.make()
        defer { fixture.delete() }
        let before = try fixture.snapshot()

        let answer = try await fixture.call(op, ["name": name, "content": Self.agentText])

        #expect(answer == error.message)
        #expect(try fixture.snapshot() == before)
    }

    // MARK: - Change events

    @Test("add agent gives one change event with the id in added")
    func addGivesOneEvent() async throws {
        let fixture = try await WriteFixture.make()
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        _ = try await fixture.call("add agent", ["name": Self.id, "content": Self.agentText])
        let event = try await fixture.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(added: [Self.id]))
        #expect(try await fixture.cursor() == event.cursor)
    }

    @Test("remove agent gives one change event with the id in removed")
    func removeGivesOneEvent() async throws {
        let fixture = try await WriteFixture.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.agentText])
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        _ = try await fixture.call("remove agent", ["name": Self.id])
        let event = try await fixture.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(removed: [Self.id]))
        #expect(try await fixture.cursor() == event.cursor)
    }

    @Test("edit agent of the winning AGENT.md gives one change event with the id in changed")
    func editOfTheAgentDocumentGivesOneEvent() async throws {
        let fixture = try await WriteFixture.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.agentText])
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        _ = try await fixture.call("edit agent", ["name": Self.id, "content": Self.noDescriptionText])
        let event = try await fixture.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(changed: [Self.id]))
        #expect(try await fixture.cursor() == event.cursor)
    }

    @Test("edit agent of a resource document gives no change event")
    func editOfAResourceDocumentGivesNoEvent() async throws {
        let fixture = try await WriteFixture.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.agentText])
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        _ = try await fixture.call(
            "edit agent", ["name": Self.id, "document": Self.notesDocument, "content": Self.notesText])

        #expect(try await fixture.cursor() == start)
    }

    @Test("edit agent of a copy that a higher layer hides gives no change event")
    func editOfAHiddenCopyGivesNoEvent() async throws {
        let fixture = try await WriteFixture.make(
            user: [AgentFolderFixture.documentPath(of: Self.id): Self.agentText],
            project: [AgentFolderFixture.documentPath(of: Self.id): Self.agentText])
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        _ = try await fixture.call("edit agent", ["name": Self.id, "content": Self.noDescriptionText])

        #expect(try await fixture.cursor() == start)
    }

    // MARK: - Verb aliases

    @Test("each verb alias of a write operation runs that operation", arguments: verbAliases)
    func verbAliasRunsTheOperation(_ alias: (op: String, action: String)) async throws {
        let existing = alias.action == "Added" ? [:] : [AgentFolderFixture.documentPath(of: Self.id): Self.agentText]
        let fixture = try await WriteFixture.make(user: existing)
        defer { fixture.delete() }

        let answer = try await fixture.call(alias.op, ["name": Self.id, "content": Self.agentText])

        #expect(answer.hasPrefix("\(alias.action) the agent `\(Self.id)`"))
    }
}

/// An `agents` tool over a `user < project` stack in temporary folders, with
/// the calls that the write tests make.
private struct WriteFixture {
    /// The user layer.
    let user: TemporaryLayer

    /// The project layer.
    let project: TemporaryLayer

    /// The tool and its runner.
    let harness: AgentsToolHarness

    /// The registry of the runner. It does not watch its layers.
    var registry: AgentRegistry {
        harness.runHarness.registry
    }

    /// Makes the two layers with the files that a test gives, and a tool
    /// over a loaded registry of the two layers.
    ///
    /// - Parameters:
    ///   - user: The files of the user layer, by path.
    ///   - project: The files of the project layer, by path.
    ///   - script: The script of the runs that the test starts. The default
    ///     is an empty script.
    /// - Returns: The fixture. The test deletes it.
    /// - Throws: The error of the file system, or of the harness.
    static func make(
        user: [String: String] = [:], project: [String: String] = [:],
        script: ScriptedAgentScript = ScriptedAgentScript([])
    ) async throws -> WriteFixture {
        let userLayer = try TemporaryLayer.make(holding: user)
        let projectLayer = try TemporaryLayer.make(holding: project)
        let registry = AgentRegistry(layers: [userLayer.userLayer, projectLayer.layer], watch: false)
        do {
            let harness = try await AgentsToolHarness.make(script: script, registry: registry)
            return WriteFixture(user: userLayer, project: projectLayer, harness: harness)
        } catch {
            try? userLayer.delete()
            try? projectLayer.delete()
            throw error
        }
    }

    /// Calls the tool with the op `operation` and the fields `fields`.
    ///
    /// - Parameters:
    ///   - operation: The `op` of the payload.
    ///   - fields: The other fields of the payload.
    /// - Returns: The answer of the tool.
    /// - Throws: The error of the tool.
    func call(_ operation: String, _ fields: [String: String]) async throws -> String {
        try await harness.call(operation, fields)
    }

    /// Reads each item of the two layers.
    ///
    /// - Returns: The contents of each item, by its path.
    /// - Throws: The error of the file system.
    func snapshot() throws -> [String: Data] {
        try TemporaryLayer.snapshot(of: [user, project])
    }

    /// Queries the root `cursor` of the `agents` endpoint of the registry.
    ///
    /// - Returns: The cursor of the newest change.
    /// - Throws: The fault of the endpoint.
    func cursor() async throws -> String {
        try await ChangeEvent.cursor(of: try registry.agentsGraph())
    }

    /// Gives the first change event after a cursor.
    ///
    /// The read first checks that the cursor moved. Thus a call that
    /// appended no event fails the test at once, and the subscription does
    /// not wait for an event that never comes (test rule T1).
    ///
    /// - Parameter start: The cursor to resume after.
    /// - Returns: The event.
    /// - Throws: The fault of the endpoint, or a failed requirement when no
    ///   event follows `start`.
    func firstEvent(after start: String) async throws -> ChangeEvent {
        try #require(try await cursor() != start, "no change event after \(start)")
        return try await ChangeEvent.first(after: start, of: try registry.agentsGraph())
    }

    /// Removes the folders of the fixture.
    func delete() {
        try? harness.delete()
        try? user.delete()
        try? project.delete()
    }
}
