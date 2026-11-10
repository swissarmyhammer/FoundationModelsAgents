import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins `AgentWriter`: the add, the edit and the remove of agent folders in
/// the user layer or the project layer of a `defaults < user < project`
/// stack.
///
/// Each row makes a new `WriterStack` in temporary folders. After each write,
/// the row reloads the registry and reads the catalog, thus the row also
/// checks that the catalog reads the file that the writer wrote.
@Suite("Agent writer")
struct AgentWriterTests {
    /// The id of the agent that most rows write.
    private static let id = AgentFolderFixture.helperID

    /// The description of the text that an add or an edit writes.
    private static let newDescription = "A new description from the writer."

    /// The text that an add or an edit writes.
    private static let newText = AgentFolderFixture.agentText(name: id, description: newDescription)

    /// The text of a document that is not `AGENT.md`.
    private static let notesText = "Notes of the agent."

    /// The ids that the layer layout reserves.
    private static let reservedIDs = ["agents", "skills", "rules", "partials"]

    /// Ids that the id rule refuses.
    private static let invalidIDs = ["Bad_ID", "a--b"]

    /// Document paths that the writer refuses for each agent.
    private static let unsafeDocuments = ["", "../x.md", "/tmp/x.md", "a/../../x.md"]

    /// Document paths of the default agent that point into the folder of a
    /// different item of the layer root.
    private static let otherItemDocuments = ["\(id)/x.md", "agents/x.md", "_skills/x.md", "_rules/x.md", "_partials/x.md"]

    // MARK: - add

    @Test("add with layer user writes <user root>/<id>/AGENT.md")
    func addInUserLayer() async throws {
        let stack = try WriterStack.make()
        defer { stack.delete() }

        let changed = try stack.writer.add(id: Self.id, content: Self.newText, layer: .user)

        #expect(changed == [stack.user.root.appendingPathComponent(AgentFolderFixture.documentPath(of: Self.id))])
        #expect(try await stack.reloadedSource(of: Self.id) == .user)
    }

    @Test("add with layer project writes <project root>/<id>/AGENT.md")
    func addInProjectLayer() async throws {
        let stack = try WriterStack.make()
        defer { stack.delete() }

        let changed = try stack.writer.add(id: Self.id, content: Self.newText, layer: .project)

        #expect(changed == [stack.project.root.appendingPathComponent(AgentFolderFixture.documentPath(of: Self.id))])
        #expect(try await stack.reloadedSource(of: Self.id) == .project)
    }

    @Test("the default layer of add is the user layer")
    func addDefaultsToUserLayer() async throws {
        let stack = try WriterStack.make()
        defer { stack.delete() }

        _ = try stack.writer.add(id: Self.id, content: Self.newText)

        #expect(try await stack.reloadedSource(of: Self.id) == .user)
    }

    @Test("add of default writes the root AGENT.md of the layer")
    func addDefaultWritesRootDocument() async throws {
        let stack = try WriterStack.make()
        defer { stack.delete() }

        let changed = try stack.writer.add(
            id: AgentFolderFixture.defaultAgentID,
            content: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName), layer: .user)

        #expect(changed == [stack.user.root.appendingPathComponent(AgentDocumentPath.documentName)])
        #expect(try await stack.reloadedSource(of: AgentFolderFixture.defaultAgentID) == .user)
    }

    @Test("add of an id that exists in the target layer gives alreadyExists and changes no file")
    func addOfExistingAgentFails() throws {
        let stack = try WriterStack.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.oldText])
        defer { stack.delete() }

        try stack.expectNoChange(.alreadyExists(id: Self.id, layer: .user)) {
            try stack.writer.add(id: Self.id, content: Self.newText, layer: .user)
        }
    }

    @Test("add of an id that exists in the dotfolder form of the target layer gives alreadyExists")
    func addOfExistingDotfolderAgentFails() throws {
        let stack = try WriterStack.make(user: [AgentDocumentPath.of(Self.id): Self.oldText])
        defer { stack.delete() }

        try stack.expectNoChange(.alreadyExists(id: Self.id, layer: .user)) {
            try stack.writer.add(id: Self.id, content: Self.newText, layer: .user)
        }
    }

    @Test("add of an id that a lower layer holds overrides it")
    func addOverridesLowerLayer() async throws {
        let stack = try WriterStack.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.oldText])
        defer { stack.delete() }

        _ = try stack.writer.add(id: Self.id, content: Self.newText, layer: .project)
        let definition = try #require(try await stack.reloadedCatalog().definition(named: Self.id))

        #expect(definition.layer.source == .project)
        #expect(definition.description == Self.newDescription)
    }

    @Test("add of an invalid id gives invalidID and changes no file", arguments: invalidIDs)
    func addOfInvalidIDFails(id: String) throws {
        let stack = try WriterStack.make()
        defer { stack.delete() }

        try stack.expectNoChange(.invalidID(id)) {
            try stack.writer.add(id: id, content: Self.newText, layer: .user)
        }
    }

    @Test("add of a reserved id gives reservedID and changes no file", arguments: reservedIDs)
    func addOfReservedIDFails(id: String) throws {
        let stack = try WriterStack.make()
        defer { stack.delete() }

        try stack.expectNoChange(.reservedID(id)) {
            try stack.writer.add(id: id, content: Self.newText, layer: .user)
        }
    }

    @Test("add into a layer with no root on disk makes the root")
    func addMakesMissingRoot() async throws {
        let stack = try WriterStack.make()
        defer { stack.delete() }
        try FileManager.default.removeItem(at: stack.project.root)

        _ = try stack.writer.add(id: Self.id, content: Self.newText, layer: .project)

        #expect(try await stack.reloadedSource(of: Self.id) == .project)
    }

    // MARK: - edit

    @Test("edit replaces the full text of AGENT.md")
    func editReplacesAgentDocument() async throws {
        let stack = try WriterStack.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.oldText])
        defer { stack.delete() }

        let changed = try stack.writer.edit(id: Self.id, content: Self.newText, layer: .user)

        #expect(changed == [stack.user.root.appendingPathComponent(AgentFolderFixture.documentPath(of: Self.id))])
        #expect(try await stack.reloadedCatalog().definition(named: Self.id)?.description == Self.newDescription)
    }

    @Test("edit with a new document path writes the document in the agent folder")
    func editWritesNewDocument() async throws {
        let stack = try WriterStack.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.oldText])
        defer { stack.delete() }

        _ = try stack.writer.edit(id: Self.id, document: Self.notesPath, content: Self.notesText, layer: .user)

        #expect(try stack.user.text(at: "\(Self.id)/\(Self.notesPath)") == Self.notesText)
        #expect(try await stack.reloadedSource(of: Self.id) == .user)
    }

    @Test("edit of default replaces the root AGENT.md of the user layer")
    func editOfDefaultReplacesRootDocument() async throws {
        let stack = try WriterStack.make(user: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName)
        ])
        defer { stack.delete() }
        let text = AgentFolderFixture.agentText(name: AgentFolderFixture.displayName, description: Self.newDescription)

        _ = try stack.writer.edit(id: AgentFolderFixture.defaultAgentID, content: text, layer: .user)

        #expect(try await stack.reloadedCatalog().defaultAgent?.description == Self.newDescription)
    }

    @Test("edit of default in a layer with no root AGENT.md gives notFound")
    func editOfDefaultWithNoRootDocumentFails() throws {
        let stack = try WriterStack.make(user: [
            AgentDocumentPath.of(AgentFolderFixture.defaultAgentID): Self.oldText
        ])
        defer { stack.delete() }

        try stack.expectNoChange(.notFound(id: AgentFolderFixture.defaultAgentID, layer: .user, existsIn: [])) {
            try stack.writer.edit(id: AgentFolderFixture.defaultAgentID, content: Self.newText, layer: .user)
        }
    }

    @Test("edit of a folder that has no AGENT.md gives notFound")
    func editOfFolderWithNoDocumentFails() throws {
        let stack = try WriterStack.make(user: ["\(Self.id)/\(Self.notesPath)": Self.notesText])
        defer { stack.delete() }

        try stack.expectNoChange(.notFound(id: Self.id, layer: .user, existsIn: [])) {
            try stack.writer.edit(id: Self.id, content: Self.newText, layer: .user)
        }
    }

    @Test("edit of an agent in the dotfolder form writes agents/<id>/AGENT.md")
    func editOfDotfolderAgent() async throws {
        let stack = try WriterStack.make(user: [AgentDocumentPath.of(Self.id): Self.oldText])
        defer { stack.delete() }

        _ = try stack.writer.edit(id: Self.id, content: Self.newText, layer: .user)

        #expect(try stack.user.text(at: AgentDocumentPath.of(Self.id)) == Self.newText)
        #expect(try await stack.reloadedCatalog().definition(named: Self.id)?.description == Self.newDescription)
    }

    @Test("edit of an agent with both forms writes the form that the catalog reads")
    func editOfBothFormsWritesFolderForm() async throws {
        let stack = try WriterStack.make(user: Self.bothForms)
        defer { stack.delete() }

        _ = try stack.writer.edit(id: Self.id, content: Self.newText, layer: .user)
        let definition = try #require(try await stack.reloadedCatalog().definition(named: Self.id))

        #expect(definition.description == Self.newDescription)
        #expect(try stack.user.text(at: AgentDocumentPath.of(Self.id)) == Self.oldText)
    }

    @Test("edit with an unsafe document path gives unsafeDocument and changes no file", arguments: unsafeDocuments)
    func editWithUnsafeDocumentFails(document: String) throws {
        let stack = try WriterStack.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.oldText])
        defer { stack.delete() }

        try stack.expectNoChange(.unsafeDocument(document)) {
            try stack.writer.edit(id: Self.id, document: document, content: Self.newText, layer: .user)
        }
    }

    @Test("edit through a symbolic link out of the agent folder gives unsafeDocument")
    func editThroughSymbolicLinkFails() throws {
        let stack = try WriterStack.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.oldText])
        defer { stack.delete() }
        let outside = stack.container.appendingPathComponent(Self.outsideFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: stack.user.root.appendingPathComponent("\(Self.id)/\(Self.linkName)"), withDestinationURL: outside)
        let document = "\(Self.linkName)/\(Self.notesPath)"

        try stack.expectNoChange(.unsafeDocument(document)) {
            try stack.writer.edit(id: Self.id, document: document, content: Self.notesText, layer: .user)
        }
    }

    @Test("edit of default into the folder of a different item gives unsafeDocument", arguments: otherItemDocuments)
    func editOfDefaultIntoOtherItemFails(document: String) throws {
        let stack = try WriterStack.make(user: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName),
            AgentFolderFixture.documentPath(of: Self.id): Self.oldText
        ])
        defer { stack.delete() }

        try stack.expectNoChange(.unsafeDocument(document)) {
            try stack.writer.edit(
                id: AgentFolderFixture.defaultAgentID, document: document, content: Self.notesText, layer: .user)
        }
    }

    @Test("edit of a reserved id gives reservedID and changes no file", arguments: reservedIDs)
    func editOfReservedIDFails(id: String) throws {
        let stack = try WriterStack.make(user: [AgentFolderFixture.documentPath(of: id): Self.oldText])
        defer { stack.delete() }

        try stack.expectNoChange(.reservedID(id)) {
            try stack.writer.edit(id: id, content: Self.newText, layer: .user)
        }
    }

    @Test("notFound names each layer where the agent exists")
    func notFoundNamesOtherLayer() throws {
        let stack = try WriterStack.make(user: [AgentFolderFixture.documentPath(of: Self.id): Self.oldText])
        defer { stack.delete() }

        #expect(throws: AgentWriterError.notFound(id: Self.id, layer: .project, existsIn: [.user])) {
            try stack.writer.edit(id: Self.id, content: Self.newText, layer: .project)
        }
    }

    @Test("the text of notFound names the user layer when the agent exists there")
    func notFoundMessageNamesOtherLayer() {
        let error = AgentWriterError.notFound(id: Self.id, layer: .project, existsIn: [.user])

        #expect(error.message.contains("'user'"))
    }

    // MARK: - remove

    @Test("remove deletes both forms of the agent in the target layer")
    func removeDeletesBothForms() throws {
        let stack = try WriterStack.make(user: Self.bothForms)
        defer { stack.delete() }

        let changed = try stack.writer.remove(id: Self.id, layer: .user)

        #expect(Set(changed.map(\.path)) == Set([
            stack.user.root.appendingPathComponent(Self.id).path,
            stack.user.root.appendingPathComponent("\(AgentDocumentPath.agentsFolderName)/\(Self.id)").path
        ]))
    }

    @Test("after remove, the catalog has no definition of the agent")
    func removeLeavesNoDefinition() async throws {
        let stack = try WriterStack.make(user: Self.bothForms)
        defer { stack.delete() }

        _ = try stack.writer.remove(id: Self.id, layer: .user)

        #expect(try await stack.reloadedCatalog().definition(named: Self.id) == nil)
    }

    @Test("remove keeps the copy of the agent in a different layer")
    func removeKeepsOtherLayer() async throws {
        let path = AgentFolderFixture.documentPath(of: Self.id)
        let stack = try WriterStack.make(user: [path: Self.oldText], project: [path: Self.newText])
        defer { stack.delete() }

        _ = try stack.writer.remove(id: Self.id, layer: .project)

        #expect(try await stack.reloadedSource(of: Self.id) == .user)
    }

    @Test("remove of default gives cannotRemoveDefault and changes no file")
    func removeOfDefaultFails() throws {
        let stack = try WriterStack.make(user: [
            AgentDocumentPath.documentName: AgentFolderFixture.agentText(name: AgentFolderFixture.displayName)
        ])
        defer { stack.delete() }

        try stack.expectNoChange(.cannotRemoveDefault) {
            try stack.writer.remove(id: AgentFolderFixture.defaultAgentID, layer: .user)
        }
    }

    @Test("remove of an agent that is not in the target layer gives notFound")
    func removeOfMissingAgentFails() throws {
        let stack = try WriterStack.make(defaults: [AgentFolderFixture.documentPath(of: Self.id): Self.oldText])
        defer { stack.delete() }

        try stack.expectNoChange(.notFound(id: Self.id, layer: .user, existsIn: [.defaults])) {
            try stack.writer.remove(id: Self.id, layer: .user)
        }
    }

    @Test("remove of a reserved id gives reservedID and changes no file", arguments: reservedIDs)
    func removeOfReservedIDFails(id: String) throws {
        let stack = try WriterStack.make(user: [AgentFolderFixture.documentPath(of: id): Self.oldText])
        defer { stack.delete() }

        try stack.expectNoChange(.reservedID(id)) {
            try stack.writer.remove(id: id, layer: .user)
        }
    }

    // MARK: - layers

    @Test("a stack with no project layer gives layerUnavailable")
    func missingProjectLayerFails() throws {
        let stack = try WriterStack.make()
        defer { stack.delete() }
        let writer = AgentWriter(localLayers: [stack.defaults.layer(source: .defaults), stack.user.userLayer])

        try stack.expectNoChange(.layerUnavailable(.project)) {
            try writer.add(id: Self.id, content: Self.newText, layer: .project)
        }
    }

    @Test("a write never goes to a defaults layer")
    func noWriteToDefaultsLayer() throws {
        let stack = try WriterStack.make()
        defer { stack.delete() }
        let writer = AgentWriter(localLayers: [stack.defaults.layer(source: .defaults)])

        try stack.expectNoChange(.layerUnavailable(.user)) {
            try writer.add(id: Self.id, content: Self.newText, layer: .user)
        }
    }

    @Test("a write never goes to a marketplace layer above the user layer")
    func noWriteToMarketplaceLayer() throws {
        let stack = try WriterStack.make()
        defer { stack.delete() }
        let writer = AgentWriter(localLayers: [stack.user.userLayer, stack.project.layer(source: .marketplace)])

        let changed = try writer.add(id: Self.id, content: Self.newText, layer: .user)

        #expect(changed == [stack.user.root.appendingPathComponent(AgentFolderFixture.documentPath(of: Self.id))])
    }

    @Test("a file system error gives writeFailed and changes no file")
    func fileSystemErrorFails() throws {
        let stack = try WriterStack.make()
        defer { stack.delete() }
        try FileManager.default.setAttributes([.posixPermissions: Self.readOnlyPermissions], ofItemAtPath: stack.user.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: Self.writablePermissions], ofItemAtPath: stack.user.root.path) }

        let before = try stack.snapshot()
        let error = #expect(throws: AgentWriterError.self) {
            try stack.writer.add(id: Self.id, content: Self.newText, layer: .user)
        }
        #expect(error.map(Self.isWriteFailure) == true)
        #expect(try stack.snapshot() == before)
    }

    @Test("each layer value has the name of the layer option of the skills tool")
    func layerValuesMatchSkillsOption() {
        #expect(AgentWriteLayer.allCases.map(\.rawValue) == ["user", "project"])
    }

    // MARK: - fixture values

    /// Tells whether `error` is a failure of the file system.
    ///
    /// - Parameter error: The error of a write.
    /// - Returns: `true` for `writeFailed`.
    private static func isWriteFailure(_ error: AgentWriterError) -> Bool {
        if case .writeFailed = error { true } else { false }
    }

    /// The text of an agent before a write.
    private static let oldText = AgentFolderFixture.agentText(name: id)

    /// A document path in a subfolder of the agent folder.
    private static let notesPath = "notes/a.md"

    /// The name of the folder outside each layer that a symbolic link points to.
    private static let outsideFolderName = "outside"

    /// The name of the symbolic link in the agent folder.
    private static let linkName = "out"

    /// The POSIX permissions of a folder that no process can write.
    private static let readOnlyPermissions = 0o555

    /// The POSIX permissions of a folder that its owner can write.
    private static let writablePermissions = 0o755

    /// One agent in both forms of one layer. The two texts are different.
    private static let bothForms = [
        AgentDocumentPath.of(id): oldText,
        AgentFolderFixture.documentPath(of: id): AgentFolderFixture.agentText(name: id, description: "Folder form.")
    ]
}

/// A `defaults < user < project` stack in temporary folders, its registry,
/// and a writer over the local layers of the registry.
private struct WriterStack {
    /// The defaults layer.
    let defaults: TemporaryLayer

    /// The user layer.
    let user: TemporaryLayer

    /// The project layer.
    let project: TemporaryLayer

    /// A folder outside each layer, for the files that a row puts outside.
    let outside: TemporaryLayer

    /// The root of `outside`.
    var container: URL {
        outside.root
    }

    /// The registry over the three layers.
    let registry: AgentRegistry

    /// The writer over the local layers of `registry`.
    let writer: AgentWriter

    /// Makes the three layers with the files that a row gives.
    ///
    /// - Parameters:
    ///   - defaults: The files of the defaults layer, by path.
    ///   - user: The files of the user layer, by path.
    ///   - project: The files of the project layer, by path.
    /// - Returns: The stack.
    /// - Throws: The error of the file system.
    static func make(
        defaults: [String: String] = [:], user: [String: String] = [:], project: [String: String] = [:]
    ) throws -> WriterStack {
        let defaultsLayer = try TemporaryLayer.make(holding: defaults)
        let userLayer = try TemporaryLayer.make(holding: user)
        let projectLayer = try TemporaryLayer.make(holding: project)
        let outside = try TemporaryLayer.makeEmpty()
        let registry = AgentRegistry(layers: [
            defaultsLayer.layer(source: .defaults), userLayer.userLayer, projectLayer.layer
        ])
        return WriterStack(
            defaults: defaultsLayer, user: userLayer, project: projectLayer, outside: outside,
            registry: registry, writer: AgentWriter(registry: registry))
    }

    /// Reloads the registry and gives its catalog.
    ///
    /// - Returns: The catalog after the reload.
    /// - Throws: The error of the reload.
    func reloadedCatalog() async throws -> AgentCatalog {
        try await registry.reload()
        return registry.catalog()
    }

    /// Reloads the registry and gives the source of the layer of an agent.
    ///
    /// - Parameter id: The id of the agent.
    /// - Returns: The source of the layer of the definition, or `nil` when the
    ///   catalog has no definition of `id`.
    /// - Throws: The error of the reload.
    func reloadedSource(of id: String) async throws -> DotfolderStack.Source? {
        try await reloadedCatalog().definition(named: id)?.layer.source
    }

    /// Reads each item under the folders of the stack.
    ///
    /// - Returns: The contents of each item, by its path.
    /// - Throws: The error of the file system, also for an item that the
    ///   read cannot get. Thus a read failure fails the test with its path,
    ///   and does not give the same value before and after a write.
    func snapshot() throws -> [String: Data] {
        try TemporaryLayer.snapshot(of: [defaults, user, project, outside])
    }

    /// Runs `operation`, and checks that it throws `expected` and that no
    /// file of the stack changes.
    ///
    /// - Parameters:
    ///   - expected: The error that `operation` must throw.
    ///   - operation: The write.
    /// - Throws: The error of the file system.
    func expectNoChange(_ expected: AgentWriterError, _ operation: () throws -> [URL]) throws {
        let before = try snapshot()
        #expect(throws: expected) { _ = try operation() }
        #expect(try snapshot() == before)
    }

    /// Removes the folders of the stack.
    func delete() {
        for layer in [defaults, user, project, outside] {
            try? layer.delete()
        }
    }
}
