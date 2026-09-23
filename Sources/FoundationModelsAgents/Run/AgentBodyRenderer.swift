import Foundation
import FoundationModelsExtras
import Marketplace

/// Renders the body of an agent at run start, in the two passes of plan.md
/// §4.3 step 3.
///
/// 1. **`$ARGUMENTS`.** The renderer puts the prompt in place of each
///    `$ARGUMENTS` of the raw body, as a `.quarantined` span of a
///    `QuarantinedText`. The render never scans a quarantined span, thus a
///    `{{ x }}` or an `{% include %}` in the prompt stays text. A body with
///    no `$ARGUMENTS` is one `.original` span.
/// 2. **Stencil.** `StenciledDotfolderStack.render(_:at:in:)` renders the
///    text as the document `agents/<id>.md` of the winning layer, with the
///    `variables` of the registry. An include walks from `agents/_partials/`
///    up to `_partials/` of the layer root. The trust comes from the layer:
///    `defaults` renders trusted, and each other layer renders untrusted.
///
/// A render error becomes `AgentRunFailure.bodyRenderFailed`.
struct AgentBodyRenderer: Sendable {
    /// The placeholder in a body that the prompt takes the place of.
    static let argumentsPlaceholder = "$ARGUMENTS"

    /// The local layers of the registry, lowest precedence first.
    let localLayers: [DotfolderStack.Layer]

    /// The values that the render interpolates.
    let variables: [String: String]

    /// Makes a renderer over the local layers and the variables of
    /// `registry`.
    ///
    /// - Parameter registry: The registry that gave the definitions to
    ///   render.
    init(registry: AgentRegistry) {
        self.localLayers = registry.localLayers
        self.variables = registry.variables
    }

    /// Renders the body of `definition` with `prompt`.
    ///
    /// - Parameters:
    ///   - definition: The agent whose body to render.
    ///   - prompt: The prompt of the run. It takes the place of each
    ///     `$ARGUMENTS` of the body, as text that the render never scans.
    /// - Returns: The rendered body: the system prompt of the run.
    /// - Throws: `AgentRunFailure.bodyRenderFailed` with the description of
    ///   the render error.
    func render(_ definition: AgentDefinition, prompt: String) throws(AgentRunFailure) -> String {
        let stack = StenciledDotfolderStack(
            base: DotfolderStack(layers: scopedLayers(of: definition)), variables: variables)
        do {
            return try stack.render(
                Self.substitutingArguments(in: definition.body, with: prompt),
                at: Self.documentPath(of: definition), in: definition.layer)
        } catch {
            throw AgentRunFailure.bodyRenderFailed(String(describing: error))
        }
    }

    /// The layers that the render of `definition` reads partials from.
    ///
    /// A marketplace document sees its own marketplace layer and the local
    /// layers. A local document sees the local layers only.
    ///
    /// - Parameter definition: The agent whose body to render.
    /// - Returns: The layers, lowest precedence first.
    private func scopedLayers(of definition: AgentDefinition) -> [DotfolderStack.Layer] {
        (definition.marketplaceLayer.map { [$0.layer] } ?? []) + localLayers
    }

    /// The path of the agent file, relative to the root of its layer:
    /// `agents/<id>.md`.
    ///
    /// - Parameter definition: The agent.
    /// - Returns: The document path of the render.
    private static func documentPath(of definition: AgentDefinition) -> String {
        "\(MarketplaceLayer.agentsDirectoryName)/\(definition.id).md"
    }

    /// Cuts `body` at each `$ARGUMENTS`, and puts `prompt` in each cut as a
    /// `.quarantined` span.
    ///
    /// - Parameters:
    ///   - body: The raw body.
    ///   - prompt: The prompt of the run.
    /// - Returns: The parts of the body as `.original` spans, with a
    ///   `.quarantined` span of `prompt` between each two parts.
    private static func substitutingArguments(in body: String, with prompt: String) -> QuarantinedText {
        let parts = body.components(separatedBy: argumentsPlaceholder)
        var builder = SpanBuilder()
        for (index, part) in parts.enumerated() {
            if index > 0 {
                builder.appendQuarantined(prompt)
            }
            builder.appendOriginal(part)
        }
        return QuarantinedText(spans: builder.finish())
    }
}
