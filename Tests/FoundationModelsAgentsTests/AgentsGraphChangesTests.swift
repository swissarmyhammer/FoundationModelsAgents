import Foundation
import FoundationModelsExtras
import Marketplace
import Testing

@testable import FoundationModelsAgents

/// The `changes(after:)` subscription and the root `cursor` of the `agents`
/// endpoint (AG-8c, EXTRAS-9 rule 9).
///
/// Each test writes its agents into a ``TemporaryLayer`` and calls
/// `reload()` itself. A reload returns after its change is in the change log
/// of the registry, thus a test reads the change with no wait: the
/// subscription replays the buffered changes after the cursor at once. Each
/// read of a stream also ends when the stream ends, and the test then fails
/// (test rule T1).
@Suite("Agents graph changes")
struct AgentsGraphChangesTests {
    // MARK: - Constants

    /// The agent that each layer holds at the start.
    private static let firstID = "alpha"

    /// The second agent that the layer of a test of several agents holds at
    /// the start.
    private static let secondID = "bravo"

    /// An agent that a test adds.
    private static let addedID = "charlie"

    /// An agent that a test adds after ``addedID``.
    private static let laterID = "delta"

    /// The description of an edited agent.
    private static let editedDescription = "An edited description."

    /// The code of a cursor that the endpoint cannot resume after.
    private static let resyncCode = "RESYNC_REQUIRED"

    /// The text between the epoch and the sequence number of a cursor of the
    /// toolkit change log, whose wire form is `<epoch>:<sequence>`.
    private static let cursorSeparator: Character = ":"

    // MARK: - added, changed, removed

    /// A new `<id>/AGENT.md` gives one event with its id in `added`, and a
    /// new cursor.
    @Test func addingAnAgentGivesItsIDInAdded() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID])
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        try fixture.writeAgent(Self.addedID)
        try await fixture.registry.reload()
        let event = try await fixture.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(added: [Self.addedID]))
        #expect(event.cursor != start)
        #expect(try await fixture.cursor() == event.cursor)
    }

    /// An edit of `<id>/AGENT.md` gives one event with its id in `changed`.
    @Test func editingAnAgentGivesItsIDInChanged() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID])
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        try fixture.writeAgent(Self.firstID, description: Self.editedDescription)
        try await fixture.registry.reload()
        let event = try await fixture.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(changed: [Self.firstID]))
        #expect(try await fixture.cursor() == event.cursor)
    }

    /// An edit of the body alone, which the `Agent` type does not give, is a
    /// change of the agent too.
    @Test func editingTheBodyGivesItsIDInChanged() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID])
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        try fixture.layer.write(
            AgentFolderFixture.agentText(name: Self.firstID, body: Self.editedDescription),
            at: AgentFolderFixture.documentPath(of: Self.firstID))
        try await fixture.registry.reload()
        let event = try await fixture.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(changed: [Self.firstID]))
    }

    /// The removal of an agent folder gives one event with its id in
    /// `removed`.
    @Test func removingAnAgentGivesItsIDInRemoved() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID, Self.secondID])
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        try fixture.layer.remove(Self.firstID)
        try await fixture.registry.reload()
        let event = try await fixture.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(removed: [Self.firstID]))
        #expect(try await fixture.cursor() == event.cursor)
    }

    /// A new diagnostic that names an agent, with no change of its file, is
    /// a change of that agent: an agent file of the old format,
    /// `agents/<id>.md`, gives an `OLD_FORMAT` warning that names the id.
    @Test func aDiagnosticOnlyChangeGivesTheAgentInChanged() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID])
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        try fixture.layer.write(
            AgentFolderFixture.agentText(name: Self.firstID),
            at: "\(MarketplaceLayer.agentsDirectoryName)/\(Self.firstID).md")
        try await fixture.registry.reload()
        let event = try await fixture.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(changed: [Self.firstID]))
    }

    // MARK: - One event for each reload

    /// One reload of several changes gives one event that lists each id,
    /// and no second event.
    @Test func oneReloadOfSeveralChangesGivesOneEvent() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID, Self.secondID])
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        try fixture.writeAgent(Self.addedID)
        try fixture.writeAgent(Self.firstID, description: Self.editedDescription)
        try fixture.layer.remove(Self.secondID)
        try await fixture.registry.reload()
        let event = try await fixture.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(added: [Self.addedID], changed: [Self.firstID], removed: [Self.secondID]))
        #expect(try await fixture.cursor() == event.cursor)
    }

    /// A reload that changes no agent appends no event: the cursor stays.
    @Test func aReloadWithNoDifferenceGivesNoEvent() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID])
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        try await fixture.registry.reload()

        #expect(try await fixture.cursor() == start)
    }

    // MARK: - Resume after a cursor

    /// `changes(after:)` gives only the events after the cursor.
    @Test func changesAfterACursorGivesOnlyTheLaterEvents() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID])
        defer { fixture.delete() }
        let start = try await fixture.cursor()
        try fixture.writeAgent(Self.addedID)
        try await fixture.registry.reload()
        let earlier = try await fixture.firstEvent(after: start)

        try fixture.writeAgent(Self.laterID)
        try await fixture.registry.reload()
        let later = try await fixture.firstEvent(after: earlier.cursor)

        #expect(later.ids == ChangedIDs(added: [Self.laterID]))
        #expect(try await fixture.cursor() == later.cursor)
    }

    /// A subscription with no cursor gives only the changes after it starts.
    @Test func changesWithNoCursorStartFromNow() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID])
        defer { fixture.delete() }
        try fixture.writeAgent(Self.addedID)
        try await fixture.registry.reload()
        var responses = try await fixture.subscribe(to: "subscription { changes { \(ChangesFixture.eventFields) } }")

        try fixture.writeAgent(Self.laterID)
        try await fixture.registry.reload()
        let event = try ChangeEvent(response: try #require(try await responses.next()), at: "changes")

        #expect(event.ids == ChangedIDs(added: [Self.laterID]))
    }

    // MARK: - Aliases

    /// `agentChanges` and `agentsChanges` name `changes`, and `since` names
    /// its `after` argument. The response tells each rewrite.
    @Test(arguments: ["agentChanges", "agentsChanges"])
    func aliasNamesTheChangesSubscription(alias: String) async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID])
        defer { fixture.delete() }
        let start = try await fixture.cursor()
        try fixture.writeAgent(Self.addedID)
        try await fixture.registry.reload()

        var responses = try await fixture.subscribe(
            to: "subscription { \(alias)(since: \"\(start)\") { \(ChangesFixture.eventFields) } }")
        let text = try #require(try await responses.next())
        let reply = try GraphQLReply(text)

        #expect(try ChangeEvent(response: text, at: alias).ids == ChangedIDs(added: [Self.addedID]))
        #expect(reply.rewrites.contains { $0.from == alias && $0.to == "changes" })
        #expect(reply.rewrites.contains { $0.from == "since" && $0.to == "after" })
    }

    // MARK: - RESYNC_REQUIRED

    /// A cursor of the change log of another registry has another epoch, and
    /// gives `RESYNC_REQUIRED`.
    @Test func aCursorOfAnotherEpochGivesResyncRequired() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID])
        defer { fixture.delete() }
        let other = try await ChangesFixture.make(ids: [Self.firstID])
        defer { other.delete() }

        let codes = try await fixture.codes(after: try await other.cursor())

        #expect(codes == [Self.resyncCode])
    }

    /// A cursor whose later events left the buffer of the change log gives
    /// `RESYNC_REQUIRED`.
    @Test func aCursorTooOldForTheBufferGivesResyncRequired() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID])
        defer { fixture.delete() }
        let start = try await fixture.cursor()

        for _ in 0...AgentRegistry.CurrentBuild.changeLogCapacity {
            await fixture.registry.currentBuild.changeLog.append(ChangedIDs(changed: [Self.firstID]))
        }
        let codes = try await fixture.codes(after: start)

        #expect(codes == [Self.resyncCode])
    }

    /// A cursor after the newest event gives `RESYNC_REQUIRED`.
    @Test func aCursorAfterTheNewestEventGivesResyncRequired() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID])
        defer { fixture.delete() }
        let newest = try await fixture.cursor()

        let codes = try await fixture.codes(after: try Self.cursor(after: newest))

        #expect(codes == [Self.resyncCode])
    }

    // MARK: - One change log for each registry

    /// Two `agents` tools over one registry, and a second endpoint that a
    /// host makes over the registry, read the one change log of the
    /// registry: each gives the same cursor.
    @Test func eachEndpointOfARegistryGivesTheSameCursor() async throws {
        let fixture = try await ChangesFixture.make(ids: [Self.firstID])
        defer { fixture.delete() }
        let first = try await AgentsToolHarness.make(registry: fixture.registry)
        defer { try? first.delete() }
        let second = try await AgentsToolHarness.make(registry: fixture.registry, grant: .messagingOnly)
        defer { try? second.delete() }
        let hostGraph = try AgentsGraph(registry: fixture.registry)

        try fixture.writeAgent(Self.addedID)
        try await fixture.registry.reload()
        let cursors = [
            try await ChangesFixture.cursor(of: try Self.endpoint(of: first.tool)),
            try await ChangesFixture.cursor(of: try Self.endpoint(of: second.tool)),
            try await ChangesFixture.cursor(of: hostGraph),
        ]

        #expect(Set(cursors) == [try await fixture.cursor()])
    }

    // MARK: - Helpers

    /// Gives the one endpoint of an `agents` tool, as a host finds it.
    ///
    /// - Parameter tool: The tool.
    /// - Returns: The endpoint.
    /// - Throws: A failed requirement when the tool gives no endpoint.
    private static func endpoint(of tool: AgentsTool) throws -> any GraphQLEndpoint {
        try #require(tool.graphQLEndpoints.first)
    }

    /// Gives a cursor after another one: the same epoch, and the next
    /// sequence number.
    ///
    /// The cursor is opaque to a client. This test reads the wire form of
    /// the toolkit change log, `<epoch>:<sequence>`, only to make a cursor
    /// that no event has yet.
    ///
    /// - Parameter cursor: The cursor.
    /// - Returns: The cursor of the next sequence number.
    /// - Throws: A failed requirement when the text is not of that form.
    private static func cursor(after cursor: String) throws -> String {
        let separator = try #require(cursor.lastIndex(of: cursorSeparator))
        let sequence = try #require(UInt64(cursor[cursor.index(after: separator)...]))
        return "\(cursor[..<separator])\(cursorSeparator)\(sequence + 1)"
    }
}

/// One event of the `changes` subscription, read from a response.
private struct ChangeEvent {
    /// The cursor that resumes after the event.
    let cursor: String

    /// The ids of the event.
    let ids: ChangedIDs

    /// Reads the event of a response.
    ///
    /// - Parameters:
    ///   - text: The JSON text of the response.
    ///   - key: The response key of the subscription field.
    /// - Throws: A failed requirement when the response has no event with a
    ///   cursor and a time.
    init(response text: String, at key: String) throws {
        let event = try GraphQLReply(text).object(key)
        cursor = try #require(event["cursor"] as? String)
        _ = try #require(event["at"] as? String)
        ids = ChangedIDs(
            added: event["added"] as? [String] ?? [], changed: event["changed"] as? [String] ?? [],
            removed: event["removed"] as? [String] ?? [])
    }
}

/// A loaded registry over one temporary layer, and its one `agents`
/// endpoint, with the calls that the change tests make.
private struct ChangesFixture {
    /// The selection of each field of an `AgentChange`.
    static let eventFields = "cursor at added changed removed"

    /// The layer of the registry.
    let layer: TemporaryLayer

    /// The registry, which is loaded.
    let registry: AgentRegistry

    /// The one endpoint of the registry.
    let graph: AgentsGraph

    /// Makes a layer with one valid agent for each id, loads a registry over
    /// it, and gets the endpoint of the registry.
    ///
    /// - Parameter ids: The ids of the agents, each at `<id>/AGENT.md`.
    /// - Returns: The fixture. The test deletes it.
    /// - Throws: The error of the file system, of the load, or of the schema
    ///   build.
    static func make(ids: [String]) async throws -> ChangesFixture {
        let layer = try AgentsGraphTests.makeLayer(ids: ids)
        let registry = AgentRegistry(layers: [layer.layer])
        do {
            try await registry.load()
            return ChangesFixture(layer: layer, registry: registry, graph: try registry.agentsGraph())
        } catch {
            try? layer.delete()
            throw error
        }
    }

    /// Writes a valid agent at `<id>/AGENT.md`.
    ///
    /// - Parameters:
    ///   - id: The id of the agent.
    ///   - description: The value of its `description` key.
    /// - Throws: The error of the file system.
    func writeAgent(_ id: String, description: String = AgentFolderFixture.description) throws {
        try layer.write(
            AgentFolderFixture.agentText(name: id, description: description),
            at: AgentFolderFixture.documentPath(of: id))
    }

    /// Deletes the layer.
    func delete() {
        try? layer.delete()
    }

    /// Queries the root `cursor` of the endpoint of the registry.
    ///
    /// - Returns: The cursor of the newest change.
    /// - Throws: The fault of the endpoint, or a failed requirement.
    func cursor() async throws -> String {
        try await Self.cursor(of: graph)
    }

    /// Queries the root `cursor` of an endpoint.
    ///
    /// - Parameter endpoint: The endpoint.
    /// - Returns: The cursor of the newest change.
    /// - Throws: The fault of the endpoint, or a failed requirement when the
    ///   response has no cursor.
    static func cursor(of endpoint: any GraphQLEndpoint) async throws -> String {
        let reply = try GraphQLReply(
            await endpoint.execute(query: "{ cursor }", variables: [:], operationName: nil, viewer: nil))
        return try #require(reply.data?["cursor"] as? String, "no cursor in \(reply.text)")
    }

    /// Starts a subscription.
    ///
    /// - Parameter document: The subscription document.
    /// - Returns: The iterator of the responses. Its `next()` gives `nil`
    ///   when the stream ends.
    /// - Throws: The fault of the endpoint.
    func subscribe(to document: String) async throws -> AsyncThrowingStream<String, Error>.AsyncIterator {
        try await graph.subscribe(query: document, variables: [:], operationName: nil, viewer: nil).makeAsyncIterator()
    }

    /// Gives the first event after a cursor.
    ///
    /// - Parameter start: The cursor to resume after.
    /// - Returns: The first event after the cursor.
    /// - Throws: The fault of the endpoint, or a failed requirement when the
    ///   stream ends with no event.
    func firstEvent(after start: String) async throws -> ChangeEvent {
        var responses = try await subscribe(
            to: "subscription { changes(after: \"\(start)\") { \(Self.eventFields) } }")
        return try ChangeEvent(response: try #require(try await responses.next()), at: "changes")
    }

    /// Gives the error codes of the first response of a subscription after
    /// a cursor.
    ///
    /// - Parameter cursor: The cursor to resume after.
    /// - Returns: The `extensions.code` of each error of the first response.
    /// - Throws: The fault of the endpoint, or a failed requirement when the
    ///   stream ends with no response.
    func codes(after cursor: String) async throws -> [String] {
        var responses = try await subscribe(to: "subscription { changes(after: \"\(cursor)\") { cursor } }")
        return try GraphQLReply(try #require(try await responses.next())).codes
    }
}
