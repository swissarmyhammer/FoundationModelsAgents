import Foundation

/// The answers of the write operations of the `agents` tool: `add agent`,
/// `edit agent` and `remove agent`.
///
/// The words of the first sentence and of the bad-layer corrective are the
/// same as the write operations of the `skills` tool (SK-6), with `agent`
/// in place of `skill`.
enum AgentsToolWriteText {
    /// The first sentence of a successful write: what the write did, to
    /// which agent, in which layer, and each file or folder that changed.
    struct Sentence: Sendable {
        /// The sentence of `add agent`.
        static let added = Sentence(action: "Added", preposition: "to")

        /// The sentence of `edit agent`.
        static let edited = Sentence(action: "Edited", preposition: "in")

        /// The sentence of `remove agent`.
        static let removed = Sentence(action: "Removed", preposition: "from")

        /// The first word of the sentence: what the write did.
        let action: String

        /// The word between the agent and the layer.
        let preposition: String

        /// Gives the sentence.
        ///
        /// - Parameters:
        ///   - id: The id of the agent.
        ///   - layer: The layer of the write.
        ///   - changed: Each file or folder that the write changed.
        /// - Returns: For example ``Added the agent `reviewer` to the user layer: `/path/reviewer/AGENT.md`.``
        func text(id: String, layer: AgentWriteLayer, changed: [URL]) -> String {
            let paths = changed.map { "`\($0.path)`" }.joined(separator: pathSeparator)
            return "\(action) the agent `\(id)` \(preposition) the \(layer.rawValue) layer: \(paths)."
        }
    }

    /// The text between two paths of one sentence.
    private static let pathSeparator = ", "

    /// The text between two parts of an answer.
    private static let partSeparator = "\n\n"

    /// The answer part of a write that does not change the catalog content
    /// of the agent.
    static let catalogUnchanged = "The catalog did not change."

    /// Gives the corrective for a `layer` value that is not a write layer.
    ///
    /// - Parameter name: The refused value.
    /// - Returns: The text, which names each write layer and the default.
    static func invalidLayer(_ name: String) -> String {
        let layers = AgentWriteLayer.allCases.map { "`\($0.rawValue)`" }.joined(separator: " or ")
        return "The layer `\(name)` is not valid. Give \(layers), or leave it out for "
            + "`\(AgentWriteLayer.user.rawValue)`."
    }

    /// Gives the report of the new catalog for one agent after a write of
    /// its `AGENT.md`.
    ///
    /// - Parameters:
    ///   - id: The id of the agent.
    ///   - catalog: The catalog after the reload.
    /// - Returns: The diagnostics of the catalog that name `id`, one line
    ///   each. When the catalog does not hold the agent (a skip), the text
    ///   says so first, thus the model can correct the file.
    static func catalogReport(of id: String, in catalog: AgentCatalog) -> String {
        let lines = catalog.diagnostics.filter { $0.agent == id }.map(line(of:))
        guard catalog.definition(named: id) != nil else {
            return (["The agent `\(id)` is not in the catalog. Correct the file with 'edit agent':"] + lines)
                .joined(separator: "\n")
        }
        guard !lines.isEmpty else {
            return "The agent `\(id)` is in the catalog with no diagnostics."
        }
        return (["The agent `\(id)` is in the catalog with these diagnostics:"] + lines).joined(separator: "\n")
    }

    /// Gives the answer part of a write that does not change the catalog
    /// content of the agent.
    ///
    /// - Parameters:
    ///   - id: The id of the agent.
    ///   - layer: The layer of the write.
    ///   - catalog: The catalog after the reload.
    /// - Returns: ``catalogUnchanged``. When a copy of a different layer
    ///   holds the id in the catalog, the text also names the layer that
    ///   wins.
    static func unchanged(id: String, layer: AgentWriteLayer, in catalog: AgentCatalog) -> String {
        guard let winner = catalog.definition(named: id)?.layer.source, winner != layer.source else {
            return catalogUnchanged
        }
        return "The catalog did not change: the copy in the \(winner) layer wins."
    }

    /// Joins the parts of an answer with a blank line.
    ///
    /// - Parameter parts: The parts, in answer order.
    /// - Returns: The answer.
    static func joined(_ parts: [String]) -> String {
        parts.joined(separator: partSeparator)
    }

    /// Gives the line of one diagnostic.
    ///
    /// - Parameter diagnostic: The diagnostic.
    /// - Returns: `- <severity> <CODE>: <message>`.
    private static func line(of diagnostic: AgentDiagnostic) -> String {
        "- \(diagnostic.severity.rawValue) \(diagnostic.code.rawValue): \(diagnostic.message)"
    }
}
