import FoundationModelsExtras

/// The data of one agent that a host shows in a list (plan.md §4.2, §12).
///
/// A listing holds no body. It holds the tier 2 data, the visibility, and
/// the provenance of the agent.
public struct AgentListing: Sendable, Equatable {
    /// The id of the agent: the file name with no `.md`.
    public let id: String

    /// The `description` key, or `nil` when the key is absent.
    public let description: String?

    /// The `model` key as text, or `nil` when the key is absent or empty.
    public let model: String?

    /// The `color` key (tier 2, data only).
    public let color: String?

    /// The `background` key (tier 2, data only).
    public let background: Bool?

    /// The keys that this package does not know, with their values.
    public let unknownFields: [String: YAMLValue]

    /// `true` when the model can see and start the agent.
    public let isModelVisible: Bool

    /// `true` when the agent is a slash command.
    public let isUserInvocable: Bool

    /// The file of the agent: the layer position, the layer root, the URL,
    /// and the marketplace.
    public let provenance: AgentDiagnostic.Provenance

    /// Makes the listing of one definition.
    ///
    /// - Parameter definition: The validated agent.
    public init(definition: AgentDefinition) {
        self.id = definition.id
        self.description = definition.description
        self.model = definition.model
        self.color = definition.color
        self.background = definition.background
        self.unknownFields = definition.unknownFields
        self.isModelVisible = definition.isModelVisible
        self.isUserInvocable = definition.isUserInvocable
        self.provenance = definition.provenance
    }
}
