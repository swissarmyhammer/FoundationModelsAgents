import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins the render of a body at run start (plan.md §4.3 step 3, §16).
///
/// Pass 1 puts the prompt in place of each `$ARGUMENTS` as a quarantined
/// span. Pass 2 renders the text with Stencil as the document
/// `agents/<id>.md` of the winning layer, with the variables of the
/// registry. A render failure is `AgentRunFailure.bodyRenderFailed`.
@Suite("Agent body renderer")
struct AgentBodyRendererTests {
    /// The prompt of each test that does not hold template text.
    private static let prompt = "func add(_ a: Int, _ b: Int) -> Int"

    /// The placeholder of the prompt in a body.
    private static let argumentsPlaceholder = "$ARGUMENTS"

    /// The variable name of the registry in each test.
    private static let projectVariable = "project"

    /// The value of `projectVariable`.
    private static let projectValue = "acme"

    /// The variables of the registry in each test.
    private static let variables = [projectVariable: projectValue]

    /// A prompt that holds a variable tag and an include tag. The include
    /// names a partial that no layer holds, thus a scan of the prompt fails.
    private static let templatePrompt = "Use {{ project }} and {% include \"x\" %} as text."

    /// The agent whose body holds `$ARGUMENTS` in the fixture library.
    private static let argumentsAgent = "test-writer"

    /// The agent whose body includes `house-rules.md`.
    private static let includingAgent = "code-reviewer"

    /// The marketplace agent that includes `house-rules.md`.
    private static let marketplaceAgent = "security-reviewer"

    /// The id of each agent that a test writes into a temporary layer.
    private static let writtenAgent = "written-agent"

    /// The path of the file of `writtenAgent`, relative to the layer root.
    private static let writtenAgentPath = "agents/\(writtenAgent).md"

    /// The heading of `_partials/house-rules.md` in the `defaults` layer.
    private static let rootHouseRules = "## House Rules"

    /// The heading of the copy in `agents/_partials/` that a test writes.
    private static let agentsHouseRules = "## Agent House Rules"

    /// The path of the copy in `agents/_partials/`, relative to the layer
    /// root.
    private static let agentsPartialPath = "agents/_partials/house-rules.md"

    /// The heading of `_partials/house-rules.md` in the fixture marketplace.
    private static let marketplaceHouseRules = "## Code Tools House Rules"

    /// The name of the partial that the include tags name.
    private static let houseRulesPartial = "house-rules.md"

    /// A body that uses a filter. The untrusted render allows no filter.
    private static let filterBody = "Name: {{ \"agent\"|\(filterName) }}."

    /// The Stencil filter of `filterBody`.
    private static let filterName = "uppercase"

    /// The word that the text of each refusal of the untrusted render holds.
    private static let untrustedRefusal = "untrusted"

    /// The render of `filterBody` under the trusted render.
    private static let renderedFilterBody = "Name: AGENT."

    /// Gives the text of an agent file with a valid frontmatter and `body`.
    ///
    /// - Parameter body: The body of the file.
    /// - Returns: The text of the file.
    private static func agentFile(body: String) -> String {
        """
        ---
        name: \(writtenAgent)
        description: An agent of a test.
        ---
        \(body)
        """
    }

    /// Loads `registry`, and gives the definition of `id`.
    ///
    /// - Parameters:
    ///   - id: The agent id.
    ///   - registry: The registry to load.
    /// - Returns: The definition.
    /// - Throws: The error of `load()`, or the error of `#require` when the
    ///   catalog has no such agent.
    private static func definition(
        _ id: String, in registry: AgentRegistry
    ) async throws -> AgentDefinition {
        try #require(try await registry.loadedCatalog().definition(named: id))
    }

    /// Gives the text of a render failure.
    ///
    /// - Parameter failure: The failure that the render threw, or `nil`.
    /// - Returns: The text of `bodyRenderFailed`, or `nil` for no failure.
    private static func renderFailureText(_ failure: AgentRunFailure?) -> String? {
        switch failure {
        case .bodyRenderFailed(let text): text
        case .agentsMdUnreadable, .toolsFailed, .contextOverflow, .modelFailed, nil: nil
        }
    }

    /// Makes a registry over one temporary layer that holds `writtenAgent`
    /// with `body`.
    ///
    /// - Parameters:
    ///   - body: The body of the agent file.
    ///   - source: The source of the layer. The trust comes from it.
    /// - Returns: The temporary layer and the registry over it.
    /// - Throws: The error of the file system.
    private static func writtenRegistry(
        body: String, source: DotfolderStack.Source
    ) throws -> (layer: TemporaryLayer, registry: AgentRegistry) {
        let layer = try TemporaryLayer.makeEmpty()
        try layer.write(agentFile(body: body), at: writtenAgentPath)
        let registry = AgentRegistry(
            layers: [DotfolderStack.Layer(source: source, root: layer.root)], variables: variables)
        return (layer, registry)
    }

    @Test("each $ARGUMENTS in the body becomes the whole prompt")
    func eachArgumentsBecomesThePrompt() async throws {
        let written = try Self.writtenRegistry(
            body: "First: $ARGUMENTS\nSecond: $ARGUMENTS\n", source: .defaults)
        defer { try? written.layer.delete() }
        let definition = try await Self.definition(Self.writtenAgent, in: written.registry)

        let rendered = try AgentBodyRenderer(registry: written.registry)
            .render(definition, prompt: Self.prompt)

        #expect(
            rendered
                == definition.body.replacingOccurrences(of: Self.argumentsPlaceholder, with: Self.prompt))
        #expect(!rendered.contains(Self.argumentsPlaceholder))
    }

    @Test("the $ARGUMENTS of a fixture body becomes the prompt")
    func fixtureArgumentsBecomeThePrompt() async throws {
        let registry = AgentRegistry(stack: FixtureLibrary.stack(), variables: Self.variables)
        let definition = try await Self.definition(Self.argumentsAgent, in: registry)

        let rendered = try AgentBodyRenderer(registry: registry).render(definition, prompt: Self.prompt)

        #expect(definition.body.contains(Self.argumentsPlaceholder))
        #expect(rendered.contains(Self.prompt))
        #expect(!rendered.contains(Self.argumentsPlaceholder))
    }

    @Test("a prompt with template tags lands as text")
    func promptTagsLandAsText() async throws {
        let registry = AgentRegistry(stack: FixtureLibrary.stack(), variables: Self.variables)
        let definition = try await Self.definition(Self.argumentsAgent, in: registry)

        let rendered = try AgentBodyRenderer(registry: registry)
            .render(definition, prompt: Self.templatePrompt)

        #expect(rendered.contains(Self.templatePrompt))
        #expect(!rendered.contains(Self.projectValue))
    }

    @Test("a body with no $ARGUMENTS renders only its own template tags")
    func bodyWithNoArgumentsRendersItsOwnTags() async throws {
        let written = try Self.writtenRegistry(
            body: "Project: {{ project }}.\nNo prompt here.\n", source: .user)
        defer { try? written.layer.delete() }
        let definition = try await Self.definition(Self.writtenAgent, in: written.registry)

        let rendered = try AgentBodyRenderer(registry: written.registry)
            .render(definition, prompt: Self.prompt)

        #expect(
            rendered
                == definition.body.replacingOccurrences(
                    of: "{{ \(Self.projectVariable) }}", with: Self.projectValue))
        #expect(!rendered.contains(Self.prompt))
    }

    @Test("an include from agents/ resolves to the _partials/ of the layer root")
    func includeResolvesToLayerRootPartials() async throws {
        let registry = AgentRegistry(
            layers: [DotfolderStack.Layer(source: .defaults, root: FixtureLibrary.defaultsDirectory)])
        let definition = try await Self.definition(Self.includingAgent, in: registry)

        let rendered = try AgentBodyRenderer(registry: registry).render(definition, prompt: Self.prompt)

        #expect(rendered.contains(Self.rootHouseRules))
    }

    @Test("a copy in agents/_partials/ wins over the copy at the layer root")
    func agentsPartialsCopyWins() async throws {
        let copy = try TemporaryLayer.copy(of: FixtureLibrary.defaultsDirectory)
        defer { try? copy.delete() }
        try copy.write("\(Self.agentsHouseRules)\n", at: Self.agentsPartialPath)
        let registry = AgentRegistry(layers: [DotfolderStack.Layer(source: .defaults, root: copy.root)])
        let definition = try await Self.definition(Self.includingAgent, in: registry)

        let rendered = try AgentBodyRenderer(registry: registry).render(definition, prompt: Self.prompt)

        #expect(rendered.contains(Self.agentsHouseRules))
        #expect(!rendered.contains(Self.rootHouseRules))
    }

    @Test("a local body that includes a partial of a marketplace only fails")
    func localBodyCannotIncludeMarketplacePartial() async throws {
        let provider = try await FixtureMarketplaceProvider.make()
        defer { try? provider.delete() }
        let local = try TemporaryLayer.makeEmpty()
        defer { try? local.delete() }
        try local.write(
            Self.agentFile(body: "{% include \"\(Self.houseRulesPartial)\" %}\n"), at: Self.writtenAgentPath)
        let registry = AgentRegistry(marketplaces: provider, stack: DotfolderStack(layers: [local.layer]))
        let renderer = AgentBodyRenderer(registry: registry)
        let marketplaceDefinition = try await Self.definition(Self.marketplaceAgent, in: registry)
        let localDefinition = try #require(registry.catalog().definition(named: Self.writtenAgent))

        let marketplaceRendered = try renderer.render(marketplaceDefinition, prompt: Self.prompt)
        let failure = #expect(throws: AgentRunFailure.self) {
            try renderer.render(localDefinition, prompt: Self.prompt)
        }

        #expect(marketplaceRendered.contains(Self.marketplaceHouseRules))
        #expect(Self.renderFailureText(failure)?.contains(Self.houseRulesPartial) == true)
    }

    @Test("a defaults body renders a filter; the same body in the user layer fails")
    func trustComesFromTheLayer() async throws {
        let trusted = try Self.writtenRegistry(body: Self.filterBody, source: .defaults)
        defer { try? trusted.layer.delete() }
        let untrusted = try Self.writtenRegistry(body: Self.filterBody, source: .user)
        defer { try? untrusted.layer.delete() }
        let trustedDefinition = try await Self.definition(Self.writtenAgent, in: trusted.registry)
        let untrustedDefinition = try await Self.definition(Self.writtenAgent, in: untrusted.registry)

        let rendered = try AgentBodyRenderer(registry: trusted.registry)
            .render(trustedDefinition, prompt: Self.prompt)
        let failure = #expect(throws: AgentRunFailure.self) {
            try AgentBodyRenderer(registry: untrusted.registry)
                .render(untrustedDefinition, prompt: Self.prompt)
        }

        #expect(rendered.contains(Self.renderedFilterBody))
        let failureText = Self.renderFailureText(failure) ?? ""
        #expect(failureText.contains(Self.untrustedRefusal))
        #expect(failureText.contains(Self.filterName))
    }
}
