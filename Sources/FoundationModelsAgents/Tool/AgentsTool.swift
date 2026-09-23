import Foundation
import FoundationModels
import FoundationModelsSkills
import Operations

/// The `agents` tool: the four operations that let a model delegate a task
/// to an agent (plan.md §9.1).
///
/// A model reads the name, the description, and the schema of a tool before
/// it plans. This tool puts the agents that it can start in two of them:
///
/// - `description` holds the fixed sentences on delegation, then the
///   model-visible agents (`AgentsToolDescription`).
/// - `parameters` is the fused schema of the operations, with the `name`
///   field made an enum of the same agents (`AgentsToolSchema`). Thus the
///   model cannot invent a name.
///
/// Both are fixed when `make(context:catalogCharacterLimit:)` makes the tool.
/// An agent that a reload adds is in `list agents` and in the next tool, not
/// in this schema. A host makes a new tool for each session and each run.
///
/// Each call goes to `operationTool`, the `OperationTool` of the `Operations`
/// runtime. It resolves the payload, dispatches the operation, and keeps the
/// retry cap.
///
/// This tool is not a code-mode surface (plan.md §9.5). A host registers it
/// directly on its session.
public struct AgentsTool: Tool {
    /// The raw payload: an `op` and the fields of one operation.
    public typealias Arguments = GeneratedContent

    /// The answer of the operation, or a corrective message.
    public typealias Output = String

    /// The tool that resolves and dispatches each call.
    public let operationTool: OperationTool<AgentsToolContext>

    /// The names that the `name` enum of `parameters` holds, in catalog
    /// order.
    ///
    /// Empty when no agent was visible when the tool was made. The `name`
    /// field is then a plain string.
    public let agentNames: [String]

    /// The fused schema, with the `name` field made an enum of `agentNames`.
    public let parameters: GenerationSchema

    /// Wraps `operationTool` and builds the schema over `agentNames`.
    ///
    /// - Parameters:
    ///   - operationTool: The tool that resolves and dispatches each call.
    ///     Its description is the description of this tool.
    ///   - agentNames: The names of the agents that the tool can start, in
    ///     catalog order.
    /// - Throws: The error of `AgentsToolSchema.make(name:operations:agentNames:)`.
    init(operationTool: OperationTool<AgentsToolContext>, agentNames: [String]) throws {
        self.operationTool = operationTool
        self.agentNames = agentNames
        parameters = try AgentsToolSchema.make(
            name: operationTool.name, operations: operationTool.operations, agentNames: agentNames)
    }

    /// The model-facing name of the tool: `agents`.
    public var name: String {
        operationTool.name
    }

    /// The description that the model reads: the fixed sentences and the
    /// agents.
    public var description: String {
        operationTool.description
    }

    /// Whether FoundationModels puts `parameters` into the prompt. The same
    /// value as `operationTool`.
    public var includesSchemaInInstructions: Bool {
        operationTool.includesSchemaInInstructions
    }

    /// Makes the `agents` tool over `context`.
    ///
    /// The tool reads the catalog of `context.runner` one time, here. It
    /// keeps the model-visible agents that `context.allowedNames` permits, in
    /// catalog order. These agents go into the description and into the
    /// `name` enum of the schema.
    ///
    /// - Parameters:
    ///   - context: The shared context of the operations.
    ///   - catalogCharacterLimit: The most characters that the agent list of
    ///     the description can have. The default is
    ///     `SkillsTool.defaultCatalogCharacterLimit`. See
    ///     `AgentsToolDescription` for the forms that make a large catalog
    ///     fit.
    /// - Returns: The tool, ready to register on a session.
    /// - Throws: The error of `OperationTool.init` or of the schema builder.
    public static func make(
        context: AgentsToolContext,
        catalogCharacterLimit: Int = SkillsTool.defaultCatalogCharacterLimit
    ) async throws -> AgentsTool {
        let agents = context.startableAgents()
        let operationTool = try OperationTool(
            name: ToolVocabulary.agentsToolName,
            description: AgentsToolDescription.make(
                agents: agents.map { AgentsToolDescription.Entry(name: $0.id, description: $0.description) },
                characterLimit: catalogCharacterLimit),
            context: context,
            operations: [
                AnyOperation(ListAgents.self),
                AnyOperation(StartAgent.self),
                AnyOperation(CheckAgent.self),
                AnyOperation(CancelAgent.self)
            ],
            resolver: OperationResolver(verbAliases: verbAliases)
        )
        return try AgentsTool(operationTool: operationTool, agentNames: agents.map(\.id))
    }

    /// The verb aliases of plan.md §9.1: `stop` → `cancel`, `run` → `start`,
    /// `status` → `check`, `show` → `list`. The resolver puts them over its
    /// default aliases, thus `show` gives `list`, not the default `get`.
    static let verbAliases: [String: String] = [
        "stop": CancelAgent.verb,
        "run": StartAgent.verb,
        "status": CheckAgent.verb,
        "show": ListAgents.verb
    ]

    /// Resolves `arguments` to one operation and dispatches it through
    /// `operationTool`.
    ///
    /// Each operation gives plain text, and `OperationTool` encodes it as a
    /// JSON string. This call decodes that string, thus the model reads the
    /// text itself (plan.md §16). A corrective of the resolver is plain text
    /// already, and the call gives it as it is.
    ///
    /// - Parameter arguments: The payload of the model.
    /// - Returns: The plain-text answer of the operation, or a corrective
    ///   message.
    /// - Throws: The error of `OperationTool.call(arguments:)`.
    public func call(arguments: GeneratedContent) async throws -> String {
        let answer = try await operationTool.call(arguments: arguments)
        return (try? JSONDecoder().decode(String.self, from: Data(answer.utf8))) ?? answer
    }
}
