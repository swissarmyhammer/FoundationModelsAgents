import Foundation
import FoundationModelsExtras
import Marketplace

// The types of the `agents` GraphQL endpoint (AG-8): the enums, and the
// objects that the resolvers give. Each object is a value made from one
// catalog of the registry, thus a response reads one catalog.
//
// Each id is a `ToolkitID`, the `ID` scalar of the toolkit
// (`addToolkitIDScalar()`): a String in the output, and a String or an Int in
// the input.

// MARK: - Enums

/// The kind of the layer that gave an agent, as the `agents` endpoint names
/// it.
enum AgentsGraphLayerName: String, Codable, CaseIterable, Sendable {
    /// The defaults folder of the host.
    case defaults = "DEFAULTS"

    /// The user layer, for example the root settings folder of the host.
    case user = "USER"

    /// The project layer: the folder of the session.
    case project = "PROJECT"

    /// A cached marketplace layer.
    case marketplace = "MARKETPLACE"

    /// Gives the name of a source of the layer stack.
    ///
    /// - Parameter source: The source of the layer.
    init(_ source: DotfolderStack.Source) {
        switch source {
        case .defaults:
            self = .defaults
        case .user:
            self = .user
        case .project:
            self = .project
        case .marketplace:
            self = .marketplace
        }
    }
}

/// How serious a diagnostic is, as the `agents` endpoint names it.
enum AgentsGraphSeverity: String, Codable, CaseIterable, Sendable {
    /// The agent loads with no change.
    case advisory = "ADVISORY"

    /// The agent loads, possibly with a changed visibility.
    case warning = "WARNING"

    /// The agent does not load.
    case skip = "SKIP"

    /// Gives the severity of a diagnostic of the catalog.
    ///
    /// - Parameter severity: The severity of the diagnostic.
    init(_ severity: AgentDiagnostic.Severity) {
        switch severity {
        case .advisory:
            self = .advisory
        case .warning:
            self = .warning
        case .skip:
            self = .skip
        }
    }
}

// MARK: - Objects

/// The `AgentLayer` object: the layer that gave an agent.
struct AgentsGraphLayer: Codable, Equatable, Sendable {
    /// The kind of the layer.
    let name: AgentsGraphLayerName

    /// The absolute path of the root folder of the layer.
    let root: String

    /// Makes the object of a layer of the stack.
    ///
    /// - Parameter layer: The layer.
    init(_ layer: DotfolderStack.Layer) {
        name = AgentsGraphLayerName(layer.source)
        root = layer.root.path
    }
}

/// The `AgentMarketplace` object: the marketplace that gave an agent.
///
/// The object has no URL of the source: a URL can hold a credential, and the
/// endpoint never gives one.
struct AgentsGraphMarketplace: Codable, Equatable, Sendable {
    /// The display id of the marketplace.
    let id: ToolkitID

    /// The commit of the snapshot, or `nil` before the first install.
    let sha: String?

    /// Makes the object of the provenance of a marketplace.
    ///
    /// - Parameter provenance: The provenance.
    init(_ provenance: MarketplaceProvenance) {
        id = ToolkitID(provenance.id)
        sha = provenance.sha
    }
}

/// The `AgentDiagnostic` object: one finding of the load of the catalog.
struct AgentsGraphDiagnostic: Codable, Equatable, Sendable {
    /// The code of the finding in `UPPER_SNAKE`, ``AgentDiagnostic/Code``.
    let code: String

    /// How serious the finding is.
    let severity: AgentsGraphSeverity

    /// The id of the agent, or `nil` when the folder name is not a valid id.
    let agent: ToolkitID?

    /// The absolute path of the file that the finding is about.
    let path: String

    /// The absolute path of the root folder of the layer of the file.
    let layerRoot: String

    /// The text of the finding.
    let message: String

    /// Makes the object of a diagnostic of the catalog.
    ///
    /// - Parameter diagnostic: The diagnostic.
    init(_ diagnostic: AgentDiagnostic) {
        code = diagnostic.code.rawValue
        severity = AgentsGraphSeverity(diagnostic.severity)
        agent = diagnostic.agent.map(ToolkitID.init(_:))
        path = diagnostic.provenance.url.path
        layerRoot = diagnostic.provenance.layerRoot.path
        message = diagnostic.message
    }

    /// Gives the objects of the diagnostics of a catalog that name one agent
    /// id.
    ///
    /// - Parameters:
    ///   - id: The agent id.
    ///   - catalog: The catalog.
    /// - Returns: The objects, in the order of the catalog.
    static func naming(_ id: String, in catalog: AgentCatalog) -> [AgentsGraphDiagnostic] {
        catalog.diagnostics.filter { $0.agent == id }.map(AgentsGraphDiagnostic.init)
    }
}

/// The `Agent` object: one agent of the catalog.
struct AgentsGraphAgent: Codable, Equatable, Sendable {
    /// The canonical id of the agent, ``AgentDefinition/id``.
    let id: ToolkitID

    /// The `description` key, or `nil` when the key is absent.
    let description: String?

    /// The `model` key, or `nil` when the key is absent or empty.
    let model: String?

    /// The `color` key, or `nil` when the key is absent.
    let color: String?

    /// The `background` key, or `nil` when the key is absent.
    let background: Bool?

    /// `true` when the model can see and start the agent.
    let isModelVisible: Bool

    /// `true` when the agent is a slash command.
    let isUserInvocable: Bool

    /// `true` for the default agent, ``AgentCatalog/defaultAgentID``.
    let isDefault: Bool

    /// The layer that gave the agent.
    let layer: AgentsGraphLayer

    /// The marketplace that gave the agent, or `nil` for a local layer.
    let marketplace: AgentsGraphMarketplace?

    /// Each diagnostic of the catalog that names the agent, in the order of
    /// the catalog.
    let diagnostics: [AgentsGraphDiagnostic]

    /// Makes the object of one agent of a catalog.
    ///
    /// - Parameters:
    ///   - definition: The agent.
    ///   - catalog: The catalog that holds the agent. It gives the
    ///     diagnostics of the agent.
    init(_ definition: AgentDefinition, in catalog: AgentCatalog) {
        id = ToolkitID(definition.id)
        description = definition.description
        model = definition.model
        color = definition.color
        background = definition.background
        isModelVisible = definition.isModelVisible
        isUserInvocable = definition.isUserInvocable
        isDefault = definition.id == AgentCatalog.defaultAgentID
        layer = AgentsGraphLayer(definition.layer)
        marketplace = definition.marketplace.map(AgentsGraphMarketplace.init)
        diagnostics = AgentsGraphDiagnostic.naming(definition.id, in: catalog)
    }
}

// MARK: - Arguments

/// The arguments of `Query.agent`.
struct AgentsGraphAgentArguments: Codable, Sendable {
    /// The id of the agent, as `start agent` takes it: the exact canonical
    /// id. An Int input names the id of its decimal text.
    let id: ToolkitID
}

/// The arguments of `Subscription.changes`.
struct AgentsGraphChangesArguments: Codable, Sendable {
    /// The cursor to resume after, or `nil` for the changes after the start
    /// of the subscription only.
    let after: String?
}
