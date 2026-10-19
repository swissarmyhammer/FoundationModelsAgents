import FoundationModels
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsAgents

/// Pins the catalog-change notice of the `agents` tool.
///
/// The description of the tool is fixed for the session. When a reload
/// changes the agents that the tool can start, each live session that
/// mounted the tool gets one `CatalogChangeNotice` of the `agents` kind.
@Suite("Agents catalog-change notice")
struct CatalogNoticeTests {
    /// The agent that each row starts with.
    private static let firstAgent = "first-agent"

    /// The agent that a reload adds.
    private static let addedAgent = "added-agent"

    /// The description of each agent file.
    private static let description = "Checks the text."

    /// A session sink that gives each catalog notice to a stream, in post
    /// order.
    private actor NoticeSink: OperationEventSink, CatalogNoticeSink {
        /// The notices, in post order.
        nonisolated let notices: AsyncStream<CatalogChangeNotice>

        /// The continuation of ``notices``.
        private nonisolated let continuation: AsyncStream<CatalogChangeNotice>.Continuation

        init() {
            (notices, continuation) = AsyncStream.makeStream()
        }

        /// Drops `event`: these tests read only the notices.
        func post(event: OperationEvent) {}

        /// Gives `notice` to ``notices``.
        func post(catalogNotice notice: CatalogChangeNotice) {
            continuation.yield(notice)
        }
    }

    /// The text of an agent file.
    ///
    /// - Parameters:
    ///   - name: The id of the agent.
    ///   - body: The body of the agent.
    /// - Returns: The file text.
    private static func agentFile(_ name: String, body: String = "You check the text.") -> String {
        """
        ---
        name: \(name)
        description: \(description)
        model: flash
        ---
        \(body)
        """
    }

    /// Writes the file of the agent `name` into `layer`.
    ///
    /// - Parameters:
    ///   - name: The id of the agent.
    ///   - layer: The layer.
    ///   - body: The body of the agent.
    /// - Throws: The error of the file system.
    private static func write(_ name: String, in layer: TemporaryLayer, body: String = "You check the text.") throws {
        try layer.write(agentFile(name, body: body), at: AgentDocumentPath.of(name))
    }

    /// Mounts `tool` on a new root session, as a host does, and gives the
    /// sink of that session.
    ///
    /// The mount requires that the session joined the notice board of the
    /// tool. Thus a test fails at once, and does not wait for a notice that
    /// never comes.
    ///
    /// - Parameter tool: The tool.
    /// - Returns: The sink and the registry of the session.
    /// - Throws: A `#require` failure when the session did not join the
    ///   board.
    private static func mount(_ tool: AgentsTool) throws -> (NoticeSink, WorkRegistry) {
        let sessionID = ULID()
        let registry = WorkRegistry(sessionID: sessionID)
        let sink = NoticeSink()
        let site = MountSite(sessionID: sessionID, runPlane: RunPlane(workRegistry: registry), sink: sink)
        _ = ToolMounting.makeWrapped(tool: tool, site: site, configuration: .synchronous)
        try #require(tool.catalogNoticeBoard.sessionIDs == [sessionID])
        return (sink, registry)
    }

    /// The notice of `added` agents that the tool can start.
    ///
    /// - Parameter added: The ids of the added agents.
    /// - Returns: The notice.
    private static func addedNotice(_ added: [String]) -> CatalogChangeNotice {
        CatalogChangeNotice(
            kind: .agents, added: added.map { CatalogEntry(name: $0, description: description) }, removed: [],
            changed: [])
    }

    @Test("a reload that adds an agent posts one notice to the session that mounted the tool")
    func aReloadThatAddsAnAgentPostsANotice() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.write(Self.firstAgent, in: layer)
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }
        let (sink, registry) = try Self.mount(harness.tool)
        defer { registry.close() }
        let descriptionBefore = harness.tool.description

        try Self.write(Self.addedAgent, in: layer)
        try await harness.runHarness.registry.reload()
        var notices = sink.notices.makeAsyncIterator()
        let notice = try #require(await notices.next())

        #expect(notice == Self.addedNotice([Self.addedAgent]))
        #expect(notice.text.contains("`\(Self.addedAgent)`: \(Self.description)"))
        #expect(harness.tool.description == descriptionBefore)
    }

    @Test("a reload that changes only the body of an agent posts no notice")
    func aBodyOnlyReloadPostsNoNotice() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.write(Self.firstAgent, in: layer)
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }
        let (sink, registry) = try Self.mount(harness.tool)
        defer { registry.close() }

        try Self.write(Self.firstAgent, in: layer, body: "You check the text again.")
        try await harness.runHarness.registry.reload()
        try Self.write(Self.addedAgent, in: layer)
        try await harness.runHarness.registry.reload()
        var notices = sink.notices.makeAsyncIterator()
        let notice = try #require(await notices.next())

        #expect(notice == Self.addedNotice([Self.addedAgent]), "the first notice is the one of the second reload")
    }

    @Test("enabled: false in a running session posts a notice that removes the agent, and enabled: true adds it back")
    func turningAnAgentOffAndOnPostsNotices() async throws {
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.write(Self.firstAgent, in: layer)
        try Self.write(Self.addedAgent, in: layer)
        let harness = try await AgentsToolHarness.make(registry: AgentRegistry(layers: [layer.layer]))
        defer { try? harness.delete() }
        let (sink, registry) = try Self.mount(harness.tool)
        defer { registry.close() }
        let disabledText = Self.agentFile(Self.addedAgent).replacingOccurrences(
            of: "model: flash\n", with: "model: flash\nenabled: false\n")

        try layer.write(disabledText, at: AgentDocumentPath.of(Self.addedAgent))
        try await harness.runHarness.registry.reload()
        try Self.write(Self.addedAgent, in: layer)
        try await harness.runHarness.registry.reload()
        // The last reload adds a marker agent. Its notice always comes, thus
        // the read ends also when a notice before it is missing.
        try Self.write(Self.markerAgent, in: layer)
        try await harness.runHarness.registry.reload()
        var notices: [CatalogChangeNotice] = []
        for await notice in sink.notices {
            notices.append(notice)
            if notice.added.contains(where: { $0.name == Self.markerAgent }) { break }
        }

        #expect(
            notices == [
                CatalogChangeNotice(
                    kind: .agents, added: [], removed: [CatalogEntry(name: Self.addedAgent, description: Self.description)],
                    changed: []),
                Self.addedNotice([Self.addedAgent]),
                Self.addedNotice([Self.markerAgent])
            ])
    }

    /// The agent that the last reload of a row adds, so that the row reads
    /// its notices up to a notice that always comes.
    private static let markerAgent = "marker-agent"

    @Test("a tool with allowed names announces only the agents that it can start")
    func aToolWithAllowedNamesAnnouncesOnlyItsAgents() async throws {
        let allowedAgent = "allowed-agent"
        let layer = try TemporaryLayer.makeEmpty()
        defer { try? layer.delete() }
        try Self.write(Self.firstAgent, in: layer)
        let harness = try await AgentsToolHarness.make(
            registry: AgentRegistry(layers: [layer.layer]), allowedNames: [Self.firstAgent, allowedAgent])
        defer { try? harness.delete() }
        let (sink, registry) = try Self.mount(harness.tool)
        defer { registry.close() }

        try Self.write(Self.addedAgent, in: layer)
        try await harness.runHarness.registry.reload()
        try Self.write(allowedAgent, in: layer)
        try await harness.runHarness.registry.reload()
        var notices = sink.notices.makeAsyncIterator()
        let notice = try #require(await notices.next())

        #expect(notice == Self.addedNotice([allowedAgent]), "the agent that the tool cannot start is not announced")
    }
}
