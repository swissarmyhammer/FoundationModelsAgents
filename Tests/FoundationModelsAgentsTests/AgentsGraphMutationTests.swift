import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import GraphQL
import Testing

/// The agent mutations of the `agents` endpoint (D190): `addAgent`,
/// `updateAgent` and `removeAgent`, with the writer of the `add agent`,
/// `edit agent` and `remove agent` operations of the `agents` tool.
///
/// Each test makes a user layer and a project layer, and a defaults layer
/// when it needs a read-only copy.
@Suite("Agents graph mutations")
struct AgentsGraphMutationTests {
    // MARK: - Constants

    /// The id of the agent that the tests write.
    private static let id = "reviewer"

    /// The id of an agent that no layer holds.
    private static let unknownID = "nobody"

    /// An id that the id rule refuses.
    private static let invalidID = "Bad_Name"

    /// The description of a new agent.
    private static let description = "Reviews a change."

    /// The new description of an update.
    private static let newDescription = "Reviews a change with care."

    /// The body of a new agent.
    private static let body = "You review the change."

    /// The `color` value of a new agent.
    private static let color = "green"

    /// The display name of the default agent.
    private static let displayName = "Default"

    /// The fields of an `Agent` that each mutation selects.
    private static let agentFields = "{ id name description model color body layer { name root } }"

    /// The `addAgent` mutation.
    private static let addMutation =
        "mutation($input: AddAgentInput!) { addAgent(input: $input) \(agentFields) }"

    /// The `updateAgent` mutation.
    private static let updateMutation =
        "mutation($input: UpdateAgentInput!) { updateAgent(input: $input) \(agentFields) }"

    /// The `removeAgent` mutation.
    private static let removeMutation =
        "mutation($input: RemoveAgentInput!) { removeAgent(input: $input) { id layer agent \(agentFields) } }"

    // MARK: - addAgent

    /// `addAgent` with no layer writes `<user root>/<id>/AGENT.md`, and gives
    /// the new agent with its name, description, color and body.
    @Test func addAgentWritesTheUserLayer() async throws {
        let layers = try Layers.make()
        defer { layers.delete() }
        let fixture = try await layers.fixture()

        let reply = try await fixture.run(
            Self.addMutation,
            variables: Self.input([
                "id": .string(Self.id), "description": .string(Self.description), "color": .string(Self.color),
                "body": .string(Self.body),
            ]))
        let agent = try reply.object("addAgent")
        let layer = try #require(agent["layer"] as? [String: Any])

        #expect(reply.codes.isEmpty, "\(reply.text)")
        #expect(agent["id"] as? String == Self.id)
        #expect(agent["name"] as? String == Self.id)
        #expect(agent["description"] as? String == Self.description)
        #expect(agent["color"] as? String == Self.color)
        #expect((agent["body"] as? String)?.contains(Self.body) == true)
        #expect(layer["name"] as? String == "USER")
        #expect(FileManager.default.fileExists(atPath: layers.documentURL(of: Self.id, in: layers.user).path))
    }

    /// `addAgent` with the layer `PROJECT` writes the project layer.
    @Test func addAgentWritesTheProjectLayer() async throws {
        let layers = try Layers.make()
        defer { layers.delete() }
        let fixture = try await layers.fixture()

        let reply = try await fixture.run(
            Self.addMutation,
            variables: Self.input([
                "id": .string(Self.id), "description": .string(Self.description), "layer": .string("PROJECT"),
            ]))

        #expect(reply.codes.isEmpty, "\(reply.text)")
        #expect(FileManager.default.fileExists(atPath: layers.documentURL(of: Self.id, in: layers.project).path))
        #expect(!FileManager.default.fileExists(atPath: layers.documentURL(of: Self.id, in: layers.user).path))
    }

    /// `addAgent` of an id that the layer holds gives `AGENT_EXISTS`.
    @Test func addAgentOfAnIDThatTheLayerHoldsIsRefused() async throws {
        let layers = try Layers.make(user: [Self.id])
        defer { layers.delete() }
        let fixture = try await layers.fixture()

        let reply = try await fixture.run(
            Self.addMutation, variables: Self.input(["id": .string(Self.id), "description": .string(Self.description)]))

        #expect(reply.codes == ["AGENT_EXISTS"])
    }

    /// `addAgent` with an id that the id rule refuses, or with an empty
    /// description, gives `INVALID_AGENT` and writes no file.
    @Test(arguments: [(invalidID, description), (id, "  ")])
    func addAgentOfAnInvalidAgentIsRefused(id: String, description: String) async throws {
        let layers = try Layers.make()
        defer { layers.delete() }
        let fixture = try await layers.fixture()

        let reply = try await fixture.run(
            Self.addMutation, variables: Self.input(["id": .string(id), "description": .string(description)]))

        #expect(reply.codes == ["INVALID_AGENT"], "\(reply.text)")
        #expect(!FileManager.default.fileExists(atPath: layers.documentURL(of: id, in: layers.user).path))
    }

    // MARK: - updateAgent

    /// `updateAgent` with only a description writes the description. The
    /// body and the other frontmatter keys stay.
    @Test func updateAgentChangesOnlyTheGivenFields() async throws {
        let layers = try Layers.make()
        defer { layers.delete() }
        try layers.user.write(
            """
            ---
            name: \(Self.id)
            description: \(Self.description)
            color: \(Self.color)
            skills: [kanban]
            ---
            \(Self.body)
            """, at: AgentFolderFixture.documentPath(of: Self.id))
        let fixture = try await layers.fixture()

        let reply = try await fixture.run(
            Self.updateMutation,
            variables: Self.input(["id": .string(Self.id), "description": .string(Self.newDescription)]))
        let agent = try reply.object("updateAgent")
        let text = try String(contentsOf: layers.documentURL(of: Self.id, in: layers.user), encoding: .utf8)

        #expect(reply.codes.isEmpty, "\(reply.text)")
        #expect(agent["description"] as? String == Self.newDescription)
        #expect(agent["color"] as? String == Self.color)
        #expect((agent["body"] as? String)?.contains(Self.body) == true)
        #expect(text.contains("kanban"))
    }

    /// `updateAgent` of the default agent writes its display name.
    @Test func updateAgentWritesTheDisplayNameOfTheDefaultAgent() async throws {
        let layers = try Layers.make()
        defer { layers.delete() }
        try layers.user.write(
            AgentFolderFixture.agentText(name: AgentFolderFixture.displayName), at: AgentDocumentPath.documentName)
        let fixture = try await layers.fixture()

        let reply = try await fixture.run(
            Self.updateMutation,
            variables: Self.input([
                "id": .string(AgentFolderFixture.defaultAgentID), "name": .string(Self.displayName),
            ]))

        #expect(reply.codes.isEmpty, "\(reply.text)")
        #expect(try reply.object("updateAgent")["name"] as? String == Self.displayName)
    }

    /// `updateAgent` with no layer writes the writable layer of the highest
    /// precedence that holds the agent: the project layer over the user
    /// layer.
    @Test func updateAgentWithNoLayerWritesTheHighestLayer() async throws {
        let layers = try Layers.make(user: [Self.id], project: [Self.id])
        defer { layers.delete() }
        let fixture = try await layers.fixture()

        let reply = try await fixture.run(
            Self.updateMutation,
            variables: Self.input(["id": .string(Self.id), "description": .string(Self.newDescription)]))
        let projectText = try String(contentsOf: layers.documentURL(of: Self.id, in: layers.project), encoding: .utf8)
        let userText = try String(contentsOf: layers.documentURL(of: Self.id, in: layers.user), encoding: .utf8)

        #expect(reply.codes.isEmpty, "\(reply.text)")
        #expect(projectText.contains(Self.newDescription))
        #expect(!userText.contains(Self.newDescription))
    }

    /// `updateAgent` of an id that no layer holds gives `NOT_FOUND`.
    @Test func updateAgentOfAnUnknownIDIsNotFound() async throws {
        let layers = try Layers.make()
        defer { layers.delete() }
        let fixture = try await layers.fixture()

        let reply = try await fixture.run(
            Self.updateMutation,
            variables: Self.input(["id": .string(Self.unknownID), "description": .string(Self.newDescription)]))

        #expect(reply.codes == ["NOT_FOUND"])
    }

    /// `updateAgent` of an agent that only the defaults layer holds gives
    /// `AGENT_READ_ONLY`, and writes no file.
    @Test func updateAgentOfADefaultsAgentIsReadOnly() async throws {
        let layers = try Layers.make(defaults: [Self.id])
        defer { layers.delete() }
        let fixture = try await layers.fixture()

        let reply = try await fixture.run(
            Self.updateMutation,
            variables: Self.input(["id": .string(Self.id), "description": .string(Self.newDescription)]))

        #expect(reply.codes == ["AGENT_READ_ONLY"])
        #expect(!FileManager.default.fileExists(atPath: layers.documentURL(of: Self.id, in: layers.user).path))
    }

    /// `updateAgent` that would give a file with a warning, here an empty
    /// description, gives `INVALID_AGENT` and does not change the file.
    @Test func updateAgentThatBreaksTheFileIsRefused() async throws {
        let layers = try Layers.make(user: [Self.id])
        defer { layers.delete() }
        let fixture = try await layers.fixture()
        let url = layers.documentURL(of: Self.id, in: layers.user)
        let before = try String(contentsOf: url, encoding: .utf8)

        let reply = try await fixture.run(
            Self.updateMutation, variables: Self.input(["id": .string(Self.id), "description": .string("")]))

        #expect(reply.codes == ["INVALID_AGENT"], "\(reply.text)")
        #expect(try String(contentsOf: url, encoding: .utf8) == before)
    }

    // MARK: - removeAgent

    /// `removeAgent` with no layer deletes the project copy, and gives the
    /// user copy that stays.
    @Test func removeAgentGivesTheCopyThatStays() async throws {
        let layers = try Layers.make(user: [Self.id], project: [Self.id])
        defer { layers.delete() }
        let fixture = try await layers.fixture()

        let reply = try await fixture.run(Self.removeMutation, variables: Self.input(["id": .string(Self.id)]))
        let payload = try reply.object("removeAgent")
        let stays = try #require(payload["agent"] as? [String: Any])
        let staysLayer = try #require(stays["layer"] as? [String: Any])

        #expect(reply.codes.isEmpty, "\(reply.text)")
        #expect(payload["layer"] as? String == "PROJECT")
        #expect(staysLayer["name"] as? String == "USER")
        #expect(!FileManager.default.fileExists(atPath: layers.documentURL(of: Self.id, in: layers.project).path))
    }

    /// `removeAgent` of the last copy gives no agent that stays.
    @Test func removeAgentOfTheLastCopyGivesNoAgent() async throws {
        let layers = try Layers.make(user: [Self.id])
        defer { layers.delete() }
        let fixture = try await layers.fixture()

        let reply = try await fixture.run(
            Self.removeMutation, variables: Self.input(["id": .string(Self.id), "layer": .string("USER")]))

        #expect(reply.codes.isEmpty, "\(reply.text)")
        #expect(try reply.object("removeAgent")["agent"] is NSNull)
    }

    // MARK: - Changes and clients

    /// Each mutation gives one change event on the `changes` subscription.
    @Test func aMutationGivesAChangeEvent() async throws {
        let layers = try Layers.make()
        defer { layers.delete() }
        let fixture = try await layers.fixture()
        let cursor = try #require(try await fixture.run("{ cursor }").data?["cursor"] as? String)

        let reply = try await fixture.run(
            Self.addMutation, variables: Self.input(["id": .string(Self.id), "description": .string(Self.description)]))
        try #require(reply.codes.isEmpty, "\(reply.text)")
        let stream = try await fixture.graph.subscribe(
            query: "subscription($after: String) { changes(after: $after) { added } }",
            variables: ["after": .string(cursor)], operationName: nil, viewer: nil)
        let first = try #require(try await stream.first { _ in true })
        let added = try GraphQLReply(first).object("changes")["added"] as? [String]

        #expect(added == [Self.id])
    }

    /// An external client cannot write: each mutation gives
    /// `EXTERNAL_CLIENT_READ_ONLY` and writes no file. A device of the user
    /// can write.
    @Test func anExternalClientCannotWrite() async throws {
        let layers = try Layers.make()
        defer { layers.delete() }
        let fixture = try await layers.fixture()
        let variables = Self.input(["id": .string(Self.id), "description": .string(Self.description)])

        let external = try GraphQLReply(
            await fixture.graph.execute(
                query: Self.addMutation, variables: variables, operationName: nil,
                viewer: GraphQLViewer(clientId: "phone", trust: .external)))
        let externalWrote = FileManager.default.fileExists(
            atPath: layers.documentURL(of: Self.id, in: layers.user).path)
        let device = try GraphQLReply(
            await fixture.graph.execute(
                query: Self.addMutation, variables: variables, operationName: nil,
                viewer: GraphQLViewer(clientId: "mac", trust: .userDevice)))

        #expect(external.codes == ["EXTERNAL_CLIENT_READ_ONLY"])
        #expect(!externalWrote)
        #expect(device.codes.isEmpty, "\(device.text)")
    }

    /// The endpoint of the registry, ``AgentRegistry/agentsGraph()``, writes
    /// too: it reloads the registry after the write.
    @Test func theEndpointOfTheRegistryWrites() async throws {
        let layers = try Layers.make()
        defer { layers.delete() }
        let registry = layers.registry()
        try await registry.load()

        let reply = try await AgentsGraphFixture.run(
            Self.addMutation, variables: Self.input(["id": .string(Self.id), "description": .string(Self.description)]),
            on: try registry.agentsGraph())

        #expect(reply.codes.isEmpty, "\(reply.text)")
        #expect(registry.catalog().definition(named: Self.id) != nil)
    }

    // MARK: - Helpers

    /// The variables of a mutation: one `input` object.
    ///
    /// - Parameter fields: The fields of the input.
    /// - Returns: The variables.
    private static func input(_ fields: [String: Map]) -> [String: Map] {
        ["input": .dictionary(.init(uniqueKeysWithValues: fields.sorted { $0.key < $1.key }))]
    }

    /// A defaults layer, a user layer and a project layer, each in its own
    /// temporary folder.
    private struct Layers {
        /// The read-only defaults layer.
        let defaults: TemporaryLayer

        /// The user layer.
        let user: TemporaryLayer

        /// The project layer.
        let project: TemporaryLayer

        /// Makes the three layers, each with a valid agent for each id.
        ///
        /// - Parameters:
        ///   - defaults: The ids of the agents of the defaults layer.
        ///   - user: The ids of the agents of the user layer.
        ///   - project: The ids of the agents of the project layer.
        /// - Returns: The layers.
        /// - Throws: An error of the file system.
        static func make(defaults: [String] = [], user: [String] = [], project: [String] = []) throws -> Layers {
            let layers = Layers(
                defaults: try TemporaryLayer.makeEmpty(), user: try TemporaryLayer.makeEmpty(),
                project: try TemporaryLayer.makeEmpty())
            for (layer, ids) in [(layers.defaults, defaults), (layers.user, user), (layers.project, project)] {
                for id in ids {
                    try layer.write(AgentFolderFixture.agentText(name: id), at: AgentFolderFixture.documentPath(of: id))
                }
            }
            return layers
        }

        /// A registry over the three layers, not loaded.
        ///
        /// - Returns: The registry.
        func registry() -> AgentRegistry {
            AgentRegistry(layers: [
                DotfolderStack.Layer(source: .defaults, root: defaults.root), user.userLayer, project.layer,
            ])
        }

        /// The loaded registry over the three layers and its endpoint.
        ///
        /// - Returns: The fixture.
        /// - Throws: The error of the load.
        func fixture() async throws -> AgentsGraphFixture {
            try await AgentsGraphFixture.make(registry: registry())
        }

        /// The URL of the document of an agent folder of one layer.
        ///
        /// - Parameters:
        ///   - id: The id of the agent.
        ///   - layer: The layer.
        /// - Returns: `<root>/<id>/AGENT.md`.
        func documentURL(of id: String, in layer: TemporaryLayer) -> URL {
            layer.root.appending(path: AgentFolderFixture.documentPath(of: id))
        }

        /// Deletes the three folders.
        func delete() {
            for layer in [defaults, user, project] {
                try? layer.delete()
            }
        }
    }
}
