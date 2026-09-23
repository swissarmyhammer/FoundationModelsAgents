import Foundation
import Marketplace

/// One finding of the agent load (plan.md §4.3, §10).
///
/// The shape is the shape of `SkillDiagnostic` of FoundationModelsSkills: a
/// severity, the agent name when it is known, the provenance of the file,
/// and a message. A diagnostic never stops the load of a different file.
public struct AgentDiagnostic: Sendable, Equatable {
    /// How serious a diagnostic is, from the least to the most serious.
    ///
    /// An `advisory` does not change how the agent loads. A `warning` comes
    /// with an agent that loads, possibly with a changed visibility. A `skip`
    /// means that the agent did not load.
    public enum Severity: String, Sendable, Equatable, CaseIterable {
        /// The agent loads with no change.
        case advisory
        /// The agent loads, possibly with a changed visibility.
        case warning
        /// The agent does not load.
        case skip
    }

    /// The file that a diagnostic is about: the layer that holds it and the
    /// URL of the file.
    public struct Provenance: Sendable, Equatable {
        /// The position of the layer in the combined layer list, lowest
        /// precedence first.
        public var layerIndex: Int

        /// The root directory of the layer.
        public var layerRoot: URL

        /// The URL of the agent file.
        public var url: URL

        /// The marketplace of the layer, or `nil` for a local layer.
        public var marketplace: MarketplaceProvenance?

        /// Creates a provenance from its field values.
        ///
        /// - Parameters:
        ///   - layerIndex: The position of the layer, lowest precedence
        ///     first.
        ///   - layerRoot: The root directory of the layer.
        ///   - url: The URL of the agent file.
        ///   - marketplace: The marketplace of the layer. The default is
        ///     `nil`, a local layer.
        public init(layerIndex: Int, layerRoot: URL, url: URL, marketplace: MarketplaceProvenance? = nil) {
            self.layerIndex = layerIndex
            self.layerRoot = layerRoot
            self.url = url
            self.marketplace = marketplace
        }
    }

    /// How serious this diagnostic is.
    public var severity: Severity

    /// The id of the agent, or `nil` when the file name is not a valid id.
    public var agent: String?

    /// The file that this diagnostic is about.
    public var provenance: Provenance

    /// The text of the diagnostic.
    public var message: String

    /// Creates a diagnostic from its field values.
    ///
    /// - Parameters:
    ///   - severity: How serious the diagnostic is.
    ///   - agent: The id of the agent, or `nil` when it is not known.
    ///   - provenance: The file that the diagnostic is about.
    ///   - message: The text of the diagnostic.
    public init(severity: Severity, agent: String?, provenance: Provenance, message: String) {
        self.severity = severity
        self.agent = agent
        self.provenance = provenance
        self.message = message
    }
}
