import Foundation
import FoundationModelsExtras
import Marketplace

/// Renders the body of an agent at run start, in two passes.
///
/// 1. **`$ARGUMENTS`.** The renderer puts the prompt in place of each
///    `$ARGUMENTS` of the raw body, as a `.quarantined` span of a
///    `QuarantinedText`. The render never scans a quarantined span, thus a
///    `{{ x }}` or an `{% include %}` in the prompt stays text. A body with
///    no `$ARGUMENTS` is one `.original` span.
/// 2. **Stencil.** `StenciledDotfolderStack.render(_:at:in:)` renders the
///    text as the document `agents/<id>/AGENT.md` of the winning layer, with
///    the `variables` and the `templateContext` of the registry. An include
///    walks from
///    `agents/<id>/_partials/` of the agent folder, to `agents/_partials/`,
///    up to `_partials/` of the layer root. The document of the agent folder
///    form is `<id>/AGENT.md`, and its include walks from `<id>/_partials/`
///    to `_partials/` of the layer root. The default agent `AGENT.md` of the
///    layer uses `_partials/` of the layer root. The trust comes from the
///    layer: `defaults` renders trusted, and each other layer renders
///    untrusted.
///
/// A render error becomes `AgentRunFailure.bodyRenderFailed`.
struct AgentBodyRenderer: Sendable {
    /// The placeholder in a body that the prompt takes the place of.
    static let argumentsPlaceholder = "$ARGUMENTS"

    /// The local layers of the registry, lowest precedence first.
    let localLayers: [DotfolderStack.Layer]

    /// The values that the render interpolates.
    let variables: [String: String]

    /// The structured values that the render interpolates, at the rung of
    /// `variables`: the session template context of the host.
    let templateContext: [String: TemplateValue]

    /// Makes a renderer over the local layers and the variables of
    /// `registry`.
    ///
    /// - Parameter registry: The registry that gave the definitions to
    ///   render.
    init(registry: AgentRegistry) {
        self.localLayers = registry.localLayers
        self.variables = registry.variables
        self.templateContext = registry.templateContext
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
            base: DotfolderStack(layers: scopedLayers(of: definition)), variables: variables,
            values: Self.templateContext(templateContext, of: definition))
        do {
            return try stack.render(
                Self.substitutingArguments(in: definition.body, with: prompt),
                at: Self.documentPath(of: definition), in: definition.layer)
        } catch {
            throw AgentRunFailure.bodyRenderFailed(String(describing: error))
        }
    }

    /// Gives the session template context as the body of `definition` sees
    /// it: `tools.agents.enabled` is `false` when a `disallowedTools` entry
    /// of the agent denies the `agents` tool. Seen live in the bench run
    /// oneplan24: the house-rules partial told the planner, an agent with
    /// `disallowedTools: [agents]`, to schedule an agent.
    ///
    /// Each other group stays as the host gave it: its tools are tools of
    /// the host, for example inside `runCode`, and only the host knows the
    /// names of a group.
    ///
    /// - Parameters:
    ///   - context: The session template context.
    ///   - definition: The agent whose body renders.
    /// - Returns: `context`, with the `agents` group off for an agent that
    ///   denies it.
    static func templateContext(
        _ context: [String: TemplateValue], of definition: AgentDefinition
    ) -> [String: TemplateValue] {
        let agentsGroup = ToolVocabulary.agentsToolName
        guard case .dictionary(var groups)? = context["tools"],
              case .dictionary(var group)? = groups[agentsGroup],
              definition.toolSelection(over: [], hasAgentsTool: true).deniesAgents
        else {
            return context
        }
        group["enabled"] = .bool(false)
        groups[agentsGroup] = .dictionary(group)
        var narrowed = context
        narrowed["tools"] = .dictionary(groups)
        return narrowed
    }

    /// The layers that the render of `definition` reads partials from.
    ///
    /// A marketplace document sees its own marketplace layer and the local
    /// layers. A local document of the dotfolder form sees the local layers
    /// only. A document of the agent folder form sees its own layer only,
    /// thus a partial of a different layer stays out of it.
    ///
    /// The scope comes from the provenance of `definition`, not from the
    /// catalog or from a layer position. Thus a definition that names a
    /// layer that the registry does not have also renders, for example the
    /// result of `AgentRegistry.rootAgent(in:id:)`.
    ///
    /// - Parameter definition: The agent whose body to render.
    /// - Returns: The layers, lowest precedence first.
    private func scopedLayers(of definition: AgentDefinition) -> [DotfolderStack.Layer] {
        guard !definition.kind.isInAgentFolderForm else { return [definition.layer] }
        return (definition.marketplaceLayer.map { [$0.layer] } ?? []) + localLayers
    }

    /// The path of the agent document, relative to the root of its layer:
    /// `agents/<id>/AGENT.md`, or `<id>/AGENT.md` or `AGENT.md` for the agent
    /// folder form.
    ///
    /// - Parameter definition: The agent.
    /// - Returns: The document path of the render.
    private static func documentPath(of definition: AgentDefinition) -> String {
        definition.kind.documentPath(of: definition.id)
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
