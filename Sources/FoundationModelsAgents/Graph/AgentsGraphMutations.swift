import FoundationModelsExtras

// The agent mutations of the `agents` endpoint (D190): `addAgent`,
// `updateAgent` and `removeAgent`. Each write goes to `AgentWriter`, the same
// writer as the `add agent`, `edit agent` and `remove agent` operations of the
// `agents` tool, and then the registry reloads. Thus the `changes`
// subscription gives one `AgentChange` for each mutation that changes the
// catalog.

// MARK: - Enums

/// A layer that a mutation of the `agents` endpoint can write.
enum AgentsGraphWriteLayer: String, Codable, CaseIterable, Sendable {
    /// The user layer, for all projects.
    case user = "USER"

    /// The project layer, for this project only.
    case project = "PROJECT"

    /// The layer of `AgentWriter` that this value names.
    var writeLayer: AgentWriteLayer {
        switch self {
        case .user: .user
        case .project: .project
        }
    }

    /// Gives the GraphQL name of a writable layer.
    ///
    /// - Parameter layer: The writable layer.
    init(_ layer: AgentWriteLayer) {
        switch layer {
        case .user: self = .user
        case .project: self = .project
        }
    }
}

// MARK: - Inputs and payloads

/// The one `input` argument of a mutation (rule 7 of EXTRAS-9).
struct AgentsGraphInputArguments<Input: Decodable & Sendable>: Decodable, Sendable {
    /// The `input` object of the mutation.
    let input: Input
}

/// The `input` object of `addAgent`.
struct AddAgentInput: Codable, Sendable {
    /// The id of the new agent: the name of its folder, or `default` for the
    /// root `AGENT.md` of the layer.
    let id: ToolkitID

    /// The display name, or `nil` for the id.
    let name: String?

    /// The description of the new agent.
    let description: String

    /// The `model` key, or `nil` for no key.
    let model: String?

    /// The `color` key, or `nil` for no key.
    let color: String?

    /// The `background` key, or `nil` for no key.
    let background: Bool?

    /// The Markdown body, or `nil` for an empty body.
    let body: String?

    /// The layer to write, or `nil` for the user layer.
    let layer: AgentsGraphWriteLayer?
}

/// The `input` object of `updateAgent`. A field that is `nil` does not
/// change, and each other key of the frontmatter stays.
struct UpdateAgentInput: Codable, Sendable {
    /// The id of the agent to change.
    let id: ToolkitID

    /// The new display name, or `nil` for no change.
    let name: String?

    /// The new description, or `nil` for no change.
    let description: String?

    /// The new `model` key, or `nil` for no change.
    let model: String?

    /// The new `color` key, or `nil` for no change.
    let color: String?

    /// The new `background` key, or `nil` for no change.
    let background: Bool?

    /// The new Markdown body, or `nil` for no change.
    let body: String?

    /// The layer to write, or `nil` for the writable layer of the highest
    /// precedence that holds the agent.
    let layer: AgentsGraphWriteLayer?

    /// The fields that the update writes.
    var fields: AgentFileFields {
        AgentFileFields(
            name: name, description: description, model: model, color: color, background: background, body: body)
    }

    /// `true` when the input changes no field.
    var changesNothing: Bool {
        name == nil && description == nil && model == nil && color == nil && background == nil && body == nil
    }
}

/// The `input` object of `removeAgent`.
struct RemoveAgentInput: Codable, Sendable {
    /// The id of the agent to delete.
    let id: ToolkitID

    /// The layer to delete from, or `nil` for the writable layer of the
    /// highest precedence that holds the agent.
    let layer: AgentsGraphWriteLayer?
}

/// The `RemoveAgentPayload` object: what `removeAgent` deleted.
struct RemoveAgentPayload: Codable, Sendable {
    /// The id of the deleted agent.
    let id: ToolkitID

    /// The layer that the mutation deleted the agent from.
    let layer: AgentsGraphWriteLayer

    /// The copy of the agent in another layer that stays, or `nil` when no
    /// copy stays.
    let agent: AgentsGraphAgent?
}

// MARK: - Errors

/// The errors of the agent mutations of the `agents` endpoint. A mutation
/// for an id that no layer holds gives the `NOT_FOUND` of the toolkit, and a
/// failed file access gives its `INTERNAL`.
enum AgentsGraphWriteError: CodedError, Equatable {
    /// `AGENT_EXISTS`: `addAgent` of an id that the layer already holds.
    case agentExists(id: String, layer: AgentsGraphWriteLayer)

    /// `AGENT_READ_ONLY`: a change of an agent that only read-only layers
    /// hold: the defaults layer or a marketplace.
    case agentReadOnly(id: String)

    /// `INVALID_AGENT`: the agent or the new file is not valid. The message
    /// tells why.
    case invalidAgent(message: String)

    /// `EXTERNAL_CLIENT_READ_ONLY`: a client that is not a device of the user
    /// sent a mutation. Such a client asks the agent of its session for the
    /// change.
    case externalClientReadOnly

    /// Each code of this type, for rule 8 of EXTRAS-9.
    static let codes = ["AGENT_EXISTS", "AGENT_READ_ONLY", "INVALID_AGENT", "EXTERNAL_CLIENT_READ_ONLY"]

    /// The code of the error.
    var code: String {
        switch self {
        case .agentExists: Self.codes[0]
        case .agentReadOnly: Self.codes[1]
        case .invalidAgent: Self.codes[2]
        case .externalClientReadOnly: Self.codes[3]
        }
    }

    /// The message of the error: what is wrong, and how to correct the call.
    var message: String {
        switch self {
        case .agentExists(let id, let layer):
            "The agent \"\(id)\" is already in the \(layer.rawValue) layer. "
                + "Use updateAgent to change it, or give another id."
        case .agentReadOnly(let id):
            "The agent \"\(id)\" is only in a read-only layer. To change it, use addAgent with the id \"\(id)\" "
                + "and the layer USER or PROJECT: that copy overrides it."
        case .invalidAgent(let message):
            message
        case .externalClientReadOnly:
            "An external client cannot change the agents. Ask the agent of your session to make the change."
        }
    }
}

// MARK: - The registry of the writes

/// The registry that the mutations of one endpoint write and reload.
///
/// The reference is weak: the registry owns its endpoint (``AgentsGraphPort``),
/// thus a strong reference would be a cycle, and the host could not release
/// the registry and stop its watcher.
final class AgentsGraphRegistryReference: Sendable {
    /// The registry, or `nil` when the host released it.
    weak let registry: AgentRegistry?

    /// Makes the reference.
    ///
    /// - Parameter registry: The registry, or `nil` for an endpoint with no
    ///   writes.
    init(_ registry: AgentRegistry?) {
        self.registry = registry
    }
}

// MARK: - Resolvers

extension AgentsGraphResolver {
    /// The kind of the id in a `NOT_FOUND` error.
    private static let notFoundKind = "agent"

    /// Resolves `Mutation.addAgent`: writes the `AGENT.md` of a new agent.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The new agent.
    /// - Returns: The agent that the catalog gives for the id after the
    ///   write. A copy of a layer with a higher precedence wins.
    /// - Throws: ``AgentsGraphWriteError`` for a refused write, or the error
    ///   of the reload.
    func addAgent(
        context: AgentsGraphContext, arguments: AgentsGraphInputArguments<AddAgentInput>
    ) async throws -> AgentsGraphAgent? {
        let registry = try writableRegistry(for: context)
        let input = arguments.input
        let id = input.id.text
        let layer = input.layer ?? .user
        let writer = AgentWriter(registry: registry)
        if writer.layers(holding: id).contains(layer.writeLayer) {
            throw AgentsGraphWriteError.agentExists(id: id, layer: layer)
        }
        let fields = AgentFileFields(
            name: input.name ?? id, description: input.description, model: input.model, color: input.color,
            background: input.background, body: input.body ?? "")
        let text = try AgentFileText.make(fields)
        try Self.validate(text, of: id, replacing: nil)
        try Self.perform { () throws(AgentWriterError) in
            _ = try writer.add(id: id, content: text, layer: layer.writeLayer)
        }
        return try await reloaded(registry, giving: id)
    }

    /// Resolves `Mutation.updateAgent`: writes the given fields into the
    /// `AGENT.md` of an agent. Each other frontmatter key stays.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The agent and the changes.
    /// - Returns: The agent that the catalog gives for the id after the
    ///   write.
    /// - Throws: `NOT_FOUND` when no layer, or not the given layer, holds
    ///   the id, ``AgentsGraphWriteError`` for a refused write, or the error
    ///   of the reload.
    func updateAgent(
        context: AgentsGraphContext, arguments: AgentsGraphInputArguments<UpdateAgentInput>
    ) async throws -> AgentsGraphAgent? {
        let registry = try writableRegistry(for: context)
        let input = arguments.input
        let id = input.id.text
        let writer = AgentWriter(registry: registry)
        let layer = try writableLayer(of: writer, holding: id, requested: input.layer, in: registry)
        guard !input.changesNothing else {
            return Self.agent(id, in: registry.catalog())
        }
        let current = try Self.performing { () throws(AgentWriterError) in
            try writer.documentText(of: id, in: layer.writeLayer)
        }
        guard let text = try AgentFileText.changed(FrontmatterDocument.split(text: current), with: input.fields) else {
            throw AgentsGraphWriteError.invalidAgent(
                message: "The frontmatter of the AGENT.md of \"\(id)\" is not a YAML mapping, thus a key cannot "
                    + "change. Ask the agent to correct the file.")
        }
        try Self.validate(text, of: id, replacing: current)
        try Self.perform { () throws(AgentWriterError) in
            _ = try writer.edit(id: id, content: text, layer: layer.writeLayer)
        }
        return try await reloaded(registry, giving: id)
    }

    /// Resolves `Mutation.removeAgent`: deletes the folder of an agent from
    /// one layer.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The agent and the layer.
    /// - Returns: The id, the layer, and the copy of the agent that stays.
    /// - Throws: `NOT_FOUND` when no layer, or not the given layer, holds
    ///   the id, ``AgentsGraphWriteError`` for a refused delete, or the error
    ///   of the reload.
    func removeAgent(
        context: AgentsGraphContext, arguments: AgentsGraphInputArguments<RemoveAgentInput>
    ) async throws -> RemoveAgentPayload? {
        let registry = try writableRegistry(for: context)
        let input = arguments.input
        let id = input.id.text
        let writer = AgentWriter(registry: registry)
        let layer = try writableLayer(of: writer, holding: id, requested: input.layer, in: registry)
        try Self.perform { () throws(AgentWriterError) in
            _ = try writer.remove(id: id, layer: layer.writeLayer)
        }
        return RemoveAgentPayload(id: input.id, layer: layer, agent: try await reloaded(registry, giving: id))
    }

    // MARK: - Support

    /// Gives the registry that a mutation of the call writes.
    ///
    /// - Parameter context: The context of the call.
    /// - Returns: The registry.
    /// - Throws: ``AgentsGraphWriteError/externalClientReadOnly`` for an
    ///   external client. ``AgentsGraphError/catalogNotLoaded`` before the
    ///   first load. `INTERNAL` when the host released the registry.
    private func writableRegistry(for context: AgentsGraphContext) throws -> AgentRegistry {
        if context.viewer?.trust == .external {
            throw AgentsGraphWriteError.externalClientReadOnly
        }
        _ = try context.loadedCatalog()
        guard let registry = registryReference.registry else {
            throw GraphQLToolkitError.internalFailure(detail: "The agent registry of the endpoint is released.")
        }
        return registry
    }

    /// The writable layer that a change of `id` writes.
    ///
    /// - Parameters:
    ///   - writer: The writer of the registry.
    ///   - id: The id of the agent.
    ///   - requested: The layer of the input, or `nil`.
    ///   - registry: The registry, for the read-only check.
    /// - Returns: `requested` when it holds the agent, or else the writable
    ///   layer of the highest precedence that holds it.
    /// - Throws: `NOT_FOUND` when no layer, or not `requested`, holds the
    ///   id. ``AgentsGraphWriteError/agentReadOnly(id:)`` when only read-only
    ///   layers hold it.
    private func writableLayer(
        of writer: AgentWriter, holding id: String, requested: AgentsGraphWriteLayer?, in registry: AgentRegistry
    ) throws -> AgentsGraphWriteLayer {
        let holders = writer.layers(holding: id)
        if let requested {
            guard holders.contains(requested.writeLayer) else {
                throw GraphQLToolkitError.notFound(kind: "\(Self.notFoundKind) in the \(requested.rawValue) layer", id: id)
            }
            return requested
        }
        if let highest = holders.last {
            return AgentsGraphWriteLayer(highest)
        }
        guard registry.catalog().definition(named: id) != nil else {
            throw GraphQLToolkitError.notFound(kind: Self.notFoundKind, id: id)
        }
        throw AgentsGraphWriteError.agentReadOnly(id: id)
    }

    /// Reloads the registry and gives the agent of an id.
    ///
    /// The reload returns after its change is in the change log, thus the
    /// `changes` subscription has the change of the mutation.
    ///
    /// - Parameters:
    ///   - registry: The registry.
    ///   - id: The id of the agent.
    /// - Returns: The agent of the new catalog, or `nil` when no agent loads
    ///   for the id.
    /// - Throws: The error of the reload.
    private func reloaded(_ registry: AgentRegistry, giving id: String) async throws -> AgentsGraphAgent? {
        try await registry.reload()
        return Self.agent(id, in: registry.catalog())
    }

    /// The agent of an id in a catalog.
    ///
    /// - Parameters:
    ///   - id: The id of the agent.
    ///   - catalog: The catalog.
    /// - Returns: The agent, or `nil` when no agent of the catalog has the id.
    private static func agent(_ id: String, in catalog: AgentCatalog) -> AgentsGraphAgent? {
        catalog.definition(named: id).map { AgentsGraphAgent($0, in: catalog) }
    }

    /// Refuses a new file that the rule table gives a finding of the
    /// severity `warning` or `skip` for, when the current file does not have
    /// the same finding. Thus a mutation does not break a valid agent, and a
    /// finding that the file had before does not stop a different change.
    ///
    /// - Parameters:
    ///   - text: The full text of the new file.
    ///   - id: The id of the agent.
    ///   - current: The full text of the current file, or `nil` for a new
    ///     agent.
    /// - Throws: ``AgentsGraphWriteError/invalidAgent(message:)`` with each
    ///   new finding.
    private static func validate(_ text: String, of id: String, replacing current: String?) throws {
        let isDefault = id == AgentCatalog.defaultAgentID
        guard isDefault || AgentDefinitionRules.isValidID(id) else {
            throw AgentsGraphWriteError.invalidAgent(message: AgentWriterError.invalidID(id).message)
        }
        let findings = { (text: String) -> [AgentFinding]? in
            FrontmatterDocument.split(text: text).frontmatter.flatMap(AgentFrontmatter.decode).map { frontmatter in
                AgentDefinitionRules.findings(id: id, frontmatter: frontmatter, checksName: !isDefault)
                    .filter { $0.severity != .advisory }
            }
        }
        guard let new = findings(text) else {
            throw AgentsGraphWriteError.invalidAgent(message: "The frontmatter of the new AGENT.md cannot be read.")
        }
        let old = Set((current.flatMap(findings) ?? []).map(\.code))
        let added = new.filter { !old.contains($0.code) }
        guard added.isEmpty else {
            throw AgentsGraphWriteError.invalidAgent(
                message: "The agent \"\(id)\" is not valid: " + added.map(\.message).joined(separator: "; ") + ".")
        }
    }

    /// Runs a write of the writer, and gives its refusal as a GraphQL error.
    ///
    /// - Parameter write: The write.
    /// - Throws: The GraphQL error of ``AgentWriterError``.
    private static func perform(_ write: () throws(AgentWriterError) -> Void) throws {
        try performing(write)
    }

    /// Runs a read or a write of the writer, and gives its refusal as a
    /// GraphQL error.
    ///
    /// - Parameter access: The read or the write.
    /// - Returns: The value of the access.
    /// - Throws: `AGENT_EXISTS`, `NOT_FOUND`, `INTERNAL` for a failed file
    ///   access, or `INVALID_AGENT` with the message of the writer.
    private static func performing<Value>(_ access: () throws(AgentWriterError) -> Value) throws -> Value {
        do {
            return try access()
        } catch {
            switch error {
            case .alreadyExists(let id, let layer):
                throw AgentsGraphWriteError.agentExists(id: id, layer: AgentsGraphWriteLayer(layer))
            case .notFound(let id, _, _):
                throw GraphQLToolkitError.notFound(kind: notFoundKind, id: id)
            case .coordinationFailed, .writeFailed:
                throw GraphQLToolkitError.internalFailure(detail: error.message)
            case .invalidID, .reservedID, .unsafeDocument, .cannotRemoveDefault, .layerUnavailable:
                throw AgentsGraphWriteError.invalidAgent(message: error.message)
            }
        }
    }
}
