import Foundation
import FoundationModelsExtras
import FoundationModelsRouter
import Marketplace

/// One validated agent: the frontmatter of one agent file after the rule
/// table, the raw body, and the provenance.
///
/// The body is the system prompt, as the file writes it. This type does not
/// render the body; the run renders it at run start.
public struct AgentDefinition: Sendable {
    /// The maximum count of characters in an id.
    static let idCharacterLimit = 64

    /// The count of characters in a `description` above which the file gets
    /// a warning.
    static let descriptionCharacterLimit = 1024

    /// The id of the agent: the file name with no `.md`.
    public let id: String

    /// The `description` key. It tells the model when to use the agent.
    public let description: String?

    /// The body of the file, raw and not rendered.
    public let body: String

    /// The `model` key, as text, or `nil` when the key is absent or empty.
    /// The runner matches it to a slot.
    public let model: String?

    /// The fold prompt of this agent, or `nil` for
    /// `CompactionPrompt.default`.
    public let compactionPrompt: CompactionPrompt?

    /// The maximum count of passes through the tool loop, or `nil` for no
    /// limit of the agent. A `maxTurns` value that is not a whole number
    /// greater than 0 gives a limit of 1 pass.
    public let maxTurns: Int?

    /// The `tools` entries, or `nil` when the key is absent. A `tools` value
    /// that is not a list of text gives only its text entries. A
    /// `disallowedTools` value that is not a list of text gives an empty
    /// list, because the deny cannot be read in full.
    public let tools: [String]?

    /// The `disallowedTools` entries. Empty when the key is absent.
    public let disallowedTools: [String]

    /// The skills to load into the instructions of a run. Empty when the key
    /// is absent.
    public let skills: [String]

    /// The `color` key (tier 2, data only).
    public let color: String?

    /// The `background` key (tier 2, data only).
    public let background: Bool?

    /// The keys that this package does not know, with their values.
    public let unknownFields: [String: YAMLValue]

    /// `true` when the model can see and start the agent: the description is
    /// valid and `disable-model-invocation` is not `true`.
    public let isModelVisible: Bool

    /// `true` when the agent is a slash command: `user-invocable` is not
    /// `false`.
    public let isUserInvocable: Bool

    /// The layer that gave the file.
    public let layer: DotfolderStack.Layer

    /// The file of the agent: the layer position, the layer root, the URL,
    /// and the marketplace.
    public let provenance: AgentDiagnostic.Provenance

    /// The marketplace layer that gave the file, or `nil` for a local layer.
    ///
    /// The render of the body uses it for the partial scope: a marketplace
    /// document sees its own marketplace and the local layers.
    public let marketplaceLayer: MarketplaceLayer?

    /// The URL of the agent file.
    public var url: URL {
        provenance.url
    }

    /// The marketplace of the layer, or `nil` for a local layer.
    public var marketplace: MarketplaceProvenance? {
        provenance.marketplace
    }

    /// The listing of this agent.
    public var listing: AgentListing {
        AgentListing(definition: self)
    }

    /// Makes a definition from one located document, and applies the rule
    /// table.
    ///
    /// A file name that is not a valid id, a missing document, and a
    /// frontmatter that did not decode each give one `skip` and `nil`. Each
    /// other rule adds a `warning` or an `advisory`, and the agent loads.
    ///
    /// - Parameters:
    ///   - id: The file name with no `.md`.
    ///   - document: The winning copy of the file, or `nil`.
    ///   - provenance: The file of the agent. The caller makes it from the
    ///     same located document. For a marketplace file, its
    ///     `marketplace` is the provenance of `marketplaceLayer`.
    ///   - marketplaceLayer: The marketplace layer that gave the file. The
    ///     default is `nil`, a local layer.
    ///   - diagnostics: The list that receives the diagnostics of the file.
    public init?(
        id: String,
        document: Located<FrontmatterDocument<AgentFrontmatter>>?,
        provenance: AgentDiagnostic.Provenance,
        marketplaceLayer: MarketplaceLayer? = nil,
        diagnostics: inout [AgentDiagnostic]
    ) {
        guard AgentDefinitionRules.isValidID(id) else {
            diagnostics.append(
                AgentDefinitionRules.invalidIDFinding(id).diagnostic(agent: nil, provenance: provenance))
            return nil
        }
        guard let document, let frontmatter = document.value.metadata else {
            diagnostics.append(
                AgentDefinitionRules.noFrontmatterFinding.diagnostic(agent: id, provenance: provenance))
            return nil
        }
        diagnostics += AgentDefinitionRules.findings(id: id, frontmatter: frontmatter).map { finding in
            finding.diagnostic(agent: id, provenance: provenance)
        }
        self.init(
            id: id, frontmatter: frontmatter, body: document.value.content, layer: document.layer,
            provenance: provenance, marketplaceLayer: marketplaceLayer)
    }

    /// Makes a definition from a frontmatter that passed the skip rules.
    ///
    /// - Parameters:
    ///   - id: The file name with no `.md`.
    ///   - frontmatter: The decoded frontmatter.
    ///   - body: The raw body of the file.
    ///   - layer: The layer that gave the file.
    ///   - provenance: The file of the agent.
    ///   - marketplaceLayer: The marketplace layer that gave the file, or
    ///     `nil` for a local layer.
    private init(
        id: String,
        frontmatter: AgentFrontmatter,
        body: String,
        layer: DotfolderStack.Layer,
        provenance: AgentDiagnostic.Provenance,
        marketplaceLayer: MarketplaceLayer?
    ) {
        let hasValidDescription = AgentDefinitionRules.holdsText(frontmatter.description)
        let incorrectKeys = AgentAccessKey.incorrectKeys(in: frontmatter)
        self.id = id
        self.description = frontmatter.description
        self.body = body
        self.model = AgentDefinitionRules.holdsText(frontmatter.model) ? frontmatter.model : nil
        self.compactionPrompt = frontmatter.compactionPrompt.map { text in
            CompactionPrompt(name: "agent/\(id)", text: text)
        }
        self.maxTurns =
            incorrectKeys.contains(.maxTurns) ? AgentAccessKey.failClosedTurnLimit : frontmatter.maxTurns
        self.tools = Self.tools(of: frontmatter, incorrectKeys: incorrectKeys)
        self.disallowedTools = frontmatter.disallowedTools ?? []
        self.skills = frontmatter.skills ?? []
        self.color = frontmatter.color
        self.background = frontmatter.background
        self.unknownFields = frontmatter.unknownFields
        self.isModelVisible = hasValidDescription && frontmatter.disableModelInvocation != true
        self.isUserInvocable = frontmatter.userInvocable != false
        self.layer = layer
        self.provenance = provenance
        self.marketplaceLayer = marketplaceLayer
    }

    /// Gives the `tools` entries that the agent gets, with the access key
    /// rule: an incorrect value gives less access.
    ///
    /// - Parameters:
    ///   - frontmatter: The decoded frontmatter.
    ///   - incorrectKeys: The access keys whose value is not correct.
    /// - Returns: No entries when the deny cannot be read in full. Only the
    ///   text entries when the `tools` value is not a list of text. Else the
    ///   `tools` value, or `nil` when the key is absent.
    private static func tools(of frontmatter: AgentFrontmatter, incorrectKeys: [AgentAccessKey]) -> [String]? {
        guard !incorrectKeys.contains(.disallowedTools) else {
            return []
        }
        return incorrectKeys.contains(.tools) ? frontmatter.tools ?? [] : frontmatter.tools
    }
}
