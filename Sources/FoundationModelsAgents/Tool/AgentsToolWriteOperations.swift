import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations

/// Makes a new agent (`add agent`, AG-9).
///
/// The write goes to ``AgentWriter/add(id:content:layer:)``, then the
/// registry reloads. Thus `start agent` of the new id starts it in the same
/// session. No gate stands in front of the write (D78, D87).
@Generable
@Operation(
    verb: "add", noun: "agent",
    description: "Make a new agent. Give its name and the full text of its AGENT.md.",
    mount: ToolMount(mode: .runToCompletion))
struct AddAgent {
    /// The id of the new agent: the name of its folder. The other names are
    /// those of `start agent` (``AgentsTool/agentNameKeys``).
    @Guide(description: "The name of the agent: the name of its folder.")
    @OperationParam(aliases: ["agent", "agentName", "agentID", "agentId", "agentType", "subagent", "subagentType"])
    var name: String

    /// The full text of the agent document.
    @Guide(description: "The full text of the file: for add agent, the whole AGENT.md with its frontmatter.")
    var content: String

    /// The layer to write, `user` or `project`, or `nil` for `user`. The
    /// guide text is one plain literal, because the `@Operation` macro reads
    /// only a plain literal into the schema. The words are agreed with the
    /// `layer` option of the `skills` tool (SK-6).
    @Guide(description: "Optional. Where to write: user (the user folder, for all projects) or project (the .agents folder of this project). Leave it out for user.")
    var layer: String?
}

extension AddAgent {
    /// Writes the new agent, reloads the registry, and reports the result.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The file that the add wrote and its layer, then the
    ///   diagnostics of the new catalog for the id, or the skip report when
    ///   the agent did not load. A corrective for a bad layer, or with the
    ///   message of ``AgentWriterError``.
    /// - Throws: The error of ``AgentRegistry/reload()``.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        try await AgentsToolWrite(id: name, layerName: layer, sentence: .added, reportsDiagnostics: true).run(
            in: context
        ) { writer, layer throws(AgentWriterError) in
            try writer.add(id: name, content: content, layer: layer)
        }
    }
}

/// Replaces the full text of one document of an agent (`edit agent`, AG-9).
///
/// The document is `AGENT.md` by default, or a different file of the agent
/// folder. The write goes to
/// ``AgentWriter/edit(id:document:content:layer:)``, then the registry
/// reloads. No gate stands in front of the write (D78, D87).
@Generable
@Operation(
    verb: "edit", noun: "agent",
    description: "Replace the full text of one file of an agent: AGENT.md, or a different file of its folder.",
    mount: ToolMount(mode: .runToCompletion))
struct EditAgent {
    /// The id of the agent. The other names are those of `start agent`
    /// (``AgentsTool/agentNameKeys``).
    @Guide(description: "The name of the agent: the name of its folder.")
    @OperationParam(aliases: ["agent", "agentName", "agentID", "agentId", "agentType", "subagent", "subagentType"])
    var name: String

    /// The full new text of the document.
    @Guide(description: "The full new text of the file.")
    var content: String

    /// The path of the document, relative to the agent folder, or `nil` for
    /// `AGENT.md`.
    @Guide(description: "Optional. The path of the file, relative to the agent folder. Leave it out for AGENT.md.")
    var document: String?

    /// The layer to write, `user` or `project`, or `nil` for `user`. The
    /// guide text is one plain literal, because the `@Operation` macro reads
    /// only a plain literal into the schema. The words are agreed with the
    /// `layer` option of the `skills` tool (SK-6).
    @Guide(description: "Optional. Where to write: user (the user folder, for all projects) or project (the .agents folder of this project). Leave it out for user.")
    var layer: String?
}

extension EditAgent {
    /// Writes the document, reloads the registry, and reports the result.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The file that the edit wrote and its layer. For an edit of
    ///   `AGENT.md`, then the diagnostics of the new catalog for the id, or
    ///   the skip report. When the catalog content of the id did not change,
    ///   a sentence that says so. A corrective for a bad layer, or with the
    ///   message of ``AgentWriterError``.
    /// - Throws: The error of ``AgentRegistry/reload()``.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        let path = document ?? AgentWriter.agentDocument
        let write = AgentsToolWrite(
            id: name, layerName: layer, sentence: .edited, reportsDiagnostics: path == AgentWriter.agentDocument)
        return try await write.run(in: context) { writer, layer throws(AgentWriterError) in
            try writer.edit(id: name, document: path, content: content, layer: layer)
        }
    }
}

/// Deletes an agent from one layer (`remove agent`, AG-9).
///
/// The write goes to ``AgentWriter/remove(id:layer:)``, then the registry
/// reloads. A copy of the agent in a different layer stays. No gate stands
/// in front of the write (D78, D87).
@Generable
@Operation(
    verb: "remove", noun: "agent",
    description: "Delete an agent folder from one layer.",
    mount: ToolMount(mode: .runToCompletion))
struct RemoveAgent {
    /// The id of the agent. The other names are those of `start agent`
    /// (``AgentsTool/agentNameKeys``).
    @Guide(description: "The name of the agent: the name of its folder.")
    @OperationParam(aliases: ["agent", "agentName", "agentID", "agentId", "agentType", "subagent", "subagentType"])
    var name: String

    /// The layer to write, `user` or `project`, or `nil` for `user`. The
    /// guide text is one plain literal, because the `@Operation` macro reads
    /// only a plain literal into the schema. The words are agreed with the
    /// `layer` option of the `skills` tool (SK-6).
    @Guide(description: "Optional. Where to write: user (the user folder, for all projects) or project (the .agents folder of this project). Leave it out for user.")
    var layer: String?
}

extension RemoveAgent {
    /// Deletes the agent folders of the layer, reloads the registry, and
    /// reports the result.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: Each folder that the remove deleted and its layer. A
    ///   corrective for a bad layer, or with the message of
    ///   ``AgentWriterError``.
    /// - Throws: The error of ``AgentRegistry/reload()``.
    func execute(in context: AgentsToolContext) async throws -> AgentsToolAnswer {
        try await AgentsToolWrite(id: name, layerName: layer, sentence: .removed, reportsDiagnostics: false).run(
            in: context
        ) { writer, layer throws(AgentWriterError) in
            try writer.remove(id: name, layer: layer)
        }
    }
}

/// The steps that `add agent`, `edit agent` and `remove agent` share: read
/// the layer, write, reload, and give the answer.
struct AgentsToolWrite {
    /// The id of the agent.
    let id: String

    /// The `layer` value of the call, or `nil` for ``AgentWriteLayer/user``.
    let layerName: String?

    /// The first sentence of a successful write.
    let sentence: AgentsToolWriteText.Sentence

    /// Whether the answer gives the diagnostics of the new catalog for the
    /// id: `true` after a write of `AGENT.md`.
    let reportsDiagnostics: Bool

    /// Reads the layer, runs `write`, reloads the registry, and gives the
    /// answer.
    ///
    /// The answer compares the catalog before the write with the catalog
    /// after the reload, with the rule of the change log of the `agents`
    /// endpoint (``AgentCatalogChanges/change(from:to:)``). Thus the answer
    /// says that the catalog did not change exactly when the reload gives no
    /// change event for the id.
    ///
    /// - Parameters:
    ///   - context: The shared context of the tool.
    ///   - write: The write, with the writer of the registry and the layer.
    ///     It gives each file or folder that it changed.
    /// - Returns: The answer, or a corrective for a bad layer or a refused
    ///   write. A refused write changes no file.
    /// - Throws: The error of ``AgentRegistry/reload()``.
    func run(
        in context: AgentsToolContext,
        _ write: (AgentWriter, AgentWriteLayer) throws(AgentWriterError) -> [URL]
    ) async throws -> AgentsToolAnswer {
        let name = layerName ?? AgentWriteLayer.user.rawValue
        guard let layer = AgentWriteLayer(rawValue: name) else {
            return .corrective(AgentsToolWriteText.invalidLayer(name))
        }
        let registry = context.runner.registry
        let before = registry.catalog()
        let changed: [URL]
        do {
            changed = try write(AgentWriter(registry: registry), layer)
        } catch {
            return .corrective(error.message)
        }
        try await registry.reload()
        let after = registry.catalog()
        var parts = [sentence.text(id: id, layer: layer, changed: changed)]
        if reportsDiagnostics {
            parts.append(AgentsToolWriteText.catalogReport(of: id, in: after))
        }
        if !Self.changes(id, from: before, to: after) {
            parts.append(AgentsToolWriteText.unchanged(id: id, layer: layer, in: after))
        }
        return .success(AgentsToolWriteText.joined(parts))
    }

    /// Tells whether the catalog content of `id` changed between two
    /// catalogs.
    ///
    /// - Parameters:
    ///   - id: The id of the agent.
    ///   - previous: The catalog before the write.
    ///   - next: The catalog after the reload.
    /// - Returns: `true` when the change of the two catalogs adds, changes or
    ///   removes `id`.
    private static func changes(_ id: String, from previous: AgentCatalog, to next: AgentCatalog) -> Bool {
        guard let change = AgentCatalogChanges.change(from: previous, to: next) else {
            return false
        }
        return (change.added + change.changed + change.removed).contains(id)
    }
}
