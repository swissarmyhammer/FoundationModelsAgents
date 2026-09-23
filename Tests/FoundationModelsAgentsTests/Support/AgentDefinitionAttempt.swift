import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras

/// One attempt to make an `AgentDefinition`: the definition, or `nil` for a
/// skip, and the diagnostics that the attempt gave.
///
/// The static members make an attempt from a `broken/agents/` fixture or
/// from an inline frontmatter text.
struct AgentDefinitionAttempt {
    /// The id of the inline documents.
    static let inlineID = "inline-agent"

    /// A valid `description` line for the inline documents.
    static let validDescription = "description: An inline agent."

    /// The layer of the inline documents.
    static let inlineLayer = DotfolderStack.Layer(
        source: .project, root: URL(fileURLWithPath: "/inline/layer", isDirectory: true))

    /// The URL of the inline documents.
    static let inlineURL = inlineLayer.root.appendingPathComponent("agents/\(inlineID).md")

    /// The layer position of the inline documents: the project layer of a
    /// `defaults < user < project` stack.
    static let inlineLayerIndex = 2

    /// The provenance of the inline documents.
    static let inlineProvenance = AgentDiagnostic.Provenance(
        layerIndex: inlineLayerIndex, layerRoot: inlineLayer.root, url: inlineURL)

    /// The body of the inline documents. It holds a `$ARGUMENTS` and a
    /// Stencil tag, which the definition must keep as raw text.
    static let inlineBody = "You review {{ project }} code.\n\n$ARGUMENTS\n"

    /// The definition, or `nil` when the file was skipped.
    let definition: AgentDefinition?

    /// The diagnostics of the attempt, in order.
    let diagnostics: [AgentDiagnostic]

    /// The severities of `diagnostics`, in order.
    var severities: [AgentDiagnostic.Severity] {
        diagnostics.map(\.severity)
    }

    /// Loads one `broken/agents/` fixture through a `FrontmatterDocumentStack`
    /// and applies the rule table.
    ///
    /// - Parameter id: The file name of the fixture, with no `.md`.
    /// - Returns: The attempt.
    static func broken(_ id: String) -> AgentDefinitionAttempt {
        let layer = DotfolderStack.Layer(
            source: .project, root: FixtureLibrary.brokenAgentsDirectory.deletingLastPathComponent())
        let documents = FrontmatterDocumentStack(
            base: DotfolderStack(layers: [layer]), decode: AgentFrontmatter.decode)
        let path = "agents/\(id).md"
        let provenance = AgentDiagnostic.Provenance(
            layerIndex: 0, layerRoot: layer.root, url: layer.root.appendingPathComponent(path))
        return make(id: id, document: documents.item(at: path), provenance: provenance)
    }

    /// Builds one inline document from `yaml` and applies the rule table.
    ///
    /// - Parameters:
    ///   - yaml: The frontmatter text between the fences.
    ///   - id: The file name. The default is `inlineID`.
    ///   - provenance: The provenance. The default is `inlineProvenance`.
    /// - Returns: The attempt.
    static func inline(
        _ yaml: String, id: String = inlineID, provenance: AgentDiagnostic.Provenance = inlineProvenance
    ) -> AgentDefinitionAttempt {
        let document = FrontmatterDocument(metadata: AgentFrontmatter.decode(yaml), content: inlineBody)
        let located = Located(url: provenance.url, layer: inlineLayer, value: document)
        return make(id: id, document: located, provenance: provenance)
    }

    /// Applies the rule table to one document.
    ///
    /// - Parameters:
    ///   - id: The file name.
    ///   - document: The located document, or `nil`.
    ///   - provenance: The provenance of the file.
    /// - Returns: The attempt.
    static func make(
        id: String,
        document: Located<FrontmatterDocument<AgentFrontmatter>>?,
        provenance: AgentDiagnostic.Provenance
    ) -> AgentDefinitionAttempt {
        var diagnostics: [AgentDiagnostic] = []
        let definition = AgentDefinition(
            id: id, document: document, provenance: provenance, diagnostics: &diagnostics)
        return AgentDefinitionAttempt(definition: definition, diagnostics: diagnostics)
    }
}
