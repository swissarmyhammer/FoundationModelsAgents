import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import FoundationModelsSkills
import Operations

/// The `agents` tool: the operations that let a model delegate a task to an
/// agent, and send messages to a run and to its caller.
///
/// A model reads the name, the description, and the schema of a tool before
/// it plans. `description` holds the fixed sentences on delegation, then the
/// agents that the tool can start (`AgentsToolDescription`). `parameters` is
/// the fused schema of the operations (`AgentsToolSchema`), and its `name`
/// field is a plain string.
///
/// The description is fixed when `make(context:catalogCharacterLimit:)`
/// makes the tool, thus the tool definition stays the same for the whole
/// session. Each call reads the live catalog: an agent that a reload adds is
/// in `list agents`, and `start agent` starts it. A name that the catalog
/// does not have gets the unknown-agent corrective. A host makes a new tool
/// for each session and each run.
///
/// The tool is `CatalogNoticing`: each session that mounts it joins its
/// ``catalogNoticeBoard``. A reload that changes the agents that the tool can
/// start posts one `CatalogChangeNotice` to each of those sessions
/// (``AgentCatalogNotices``).
///
/// Each call goes to `operationTool`, the `OperationTool` of the `Operations`
/// runtime. It resolves the payload, dispatches the operation, and keeps the
/// retry cap.
///
/// In a Router session each call runs with the mount of its operation
/// (``mount(for:)``). `start agent` is a background call: the body waits for
/// the run that it started. A run that ends in the settle period of the
/// session gives its final message to the model as the answer of the call. A
/// run that continues gives the pending envelope of the Router, and its
/// final message comes to the caller as mail when the run ends. The tool
/// states no `inlineSettleGrace` of its own. `list agents`, `find agents`,
/// `check agent`, `cancel agent`, `send agent`, and `send caller` are
/// synchronous calls: their real answer comes back in band.
///
/// This tool is not a code-mode surface. A host registers it directly on
/// its session.
public struct AgentsTool: Tool {
    /// The raw payload: an `op` and the fields of one operation.
    public typealias Arguments = GeneratedContent

    /// The answer of the operation, or a corrective message.
    public typealias Output = String

    /// The tool that resolves and dispatches each call.
    public let operationTool: OperationTool<AgentsToolContext>

    /// The fused schema of the operations.
    public let parameters: GenerationSchema

    /// The shared context of the operations.
    let context: AgentsToolContext

    /// The notices of the catalog changes after the tool was made.
    let notices: AgentCatalogNotices

    /// Wraps `operationTool` and builds the schema of its operations.
    ///
    /// - Parameters:
    ///   - operationTool: The tool that resolves and dispatches each call.
    ///     Its description is the description of this tool.
    ///   - context: The shared context of the operations.
    ///   - notices: The notices of the catalog changes after the tool was
    ///     made.
    /// - Throws: The error of `AgentsToolSchema.make(name:operations:)`.
    init(
        operationTool: OperationTool<AgentsToolContext>, context: AgentsToolContext, notices: AgentCatalogNotices
    ) throws {
        self.operationTool = operationTool
        self.context = context
        self.notices = notices
        parameters = try AgentsToolSchema.make(name: operationTool.name, operations: operationTool.operations)
    }

    /// The model-facing name of the tool: `agents`.
    public var name: String {
        operationTool.name
    }

    /// The description that the model reads: the fixed sentences and the
    /// agents, or the short text of a tool with only the message operations.
    /// The tool of a run that has a caller adds the caller sentence.
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
    /// The grant of `context` selects the operations of the tool:
    ///
    /// - `full`: each operation. The tool reads the catalog of
    ///   `context.runner` one time, here. It keeps the model-visible agents
    ///   that `context.allowedNames` permits, in catalog order. These agents
    ///   go into the description. The tool subscribes to the reloads of the
    ///   registry before that read, and posts a notice for each later change.
    /// - `messagingOnly`: only the message operations. The tool does not
    ///   read the catalog, its short description names no agent, and it
    ///   posts no notice.
    ///
    /// - Parameters:
    ///   - context: The shared context of the operations.
    ///   - catalogCharacterLimit: The most characters that the agent list of
    ///     the description can have. The default is
    ///     `SkillsTool.defaultCatalogCharacterLimit`. See
    ///     `AgentsToolDescription` for the forms that make a large catalog
    ///     fit. A tool with only the message operations has no agent list.
    /// - Returns: The tool, ready to register on a session.
    /// - Throws: ``AgentRunnerError/catalogNotLoaded`` for each operation
    ///   before the first `AgentRegistry.load()` of the registry of
    ///   `context.runner`, or the error of `OperationTool.init` or of the
    ///   schema builder.
    public static func make(
        context: AgentsToolContext,
        catalogCharacterLimit: Int = SkillsTool.defaultCatalogCharacterLimit
    ) async throws -> AgentsTool {
        switch context.grant {
        case .full:
            guard context.runner.registry.isLoaded else {
                throw AgentRunnerError.catalogNotLoaded
            }
            let reloads = context.runner.registry.onReload
            let agents = context.startableAgents()
            let description = AgentsToolDescription.make(
                agents: agents.map(AgentsToolDescription.Entry.init), characterLimit: catalogCharacterLimit)
            let notices = AgentCatalogNotices(context: context, known: agents, reloads: reloads)
            return try make(context: context, description: description, notices: notices)
        case .messagingOnly:
            let notices = AgentCatalogNotices(context: context, known: [], reloads: AsyncStream { $0.finish() })
            return try make(context: context, description: AgentsToolDescription.messaging, notices: notices)
        }
    }

    /// Makes the `agents` tool over `context` with the operations of its
    /// grant (``operations(of:)``).
    ///
    /// When the run of the tool has a caller, the description ends with the
    /// caller sentence (``AgentsToolDescription/addingCaller(to:callerID:)``).
    ///
    /// - Parameters:
    ///   - context: The shared context of the operations.
    ///   - description: The description of the grant.
    ///   - notices: The notices of the catalog changes after the tool was
    ///     made.
    /// - Returns: The tool.
    /// - Throws: The error of `OperationTool.init` or of the schema builder.
    private static func make(
        context: AgentsToolContext, description: String, notices: AgentCatalogNotices
    ) throws -> AgentsTool {
        let callerID = context.callerLink?.sessionID
        let operationTool = try OperationTool(
            name: ToolVocabulary.agentsToolName,
            description: AgentsToolDescription.addingCaller(to: description, callerID: callerID),
            context: context,
            operations: operations(of: context.grant),
            resolver: OperationResolver(verbAliases: verbAliases, nounAliases: nounAliases)
        )
        return try AgentsTool(operationTool: operationTool, context: context, notices: notices)
    }

    /// Gives the operations of a tool with `grant`, in tool order.
    ///
    /// - Parameter grant: The grant of the tool.
    /// - Returns: The message operations for
    ///   ``AgentsToolContext/Grant/messagingOnly``. For
    ///   ``AgentsToolContext/Grant/full``, the operations that list, find,
    ///   start, check, and cancel agents, then the message operations.
    private static func operations(of grant: AgentsToolContext.Grant) -> [AnyOperation<AgentsToolContext>] {
        let messageOperations = [AnyOperation(SendAgent.self), AnyOperation(SendCaller.self)]
        switch grant {
        case .full:
            return [
                AnyOperation(ListAgents.self),
                AnyOperation(FindAgents.self),
                AnyOperation(StartAgent.self),
                AnyOperation(CheckAgent.self),
                AnyOperation(CancelAgent.self)
            ] + messageOperations
        case .messagingOnly:
            return messageOperations
        }
    }

    /// The verb aliases of the tool: `stop` → `cancel`, `run` → `start`,
    /// `status` → `check`, `show` → `list`. The resolver puts them over its
    /// default aliases, thus `show` gives `list`, not the default `get`.
    static let verbAliases: [String: String] = [
        "stop": CancelAgent.verb,
        "run": StartAgent.verb,
        "status": CheckAgent.verb,
        "show": ListAgents.verb
    ]

    /// The noun aliases of the tool: `parent` → `caller`. Thus
    /// `send parent` gives `send caller`.
    static let nounAliases: [String: String] = [
        "parent": SendCaller.noun
    ]

    /// Resolves `arguments` to one operation and dispatches it through
    /// `operationTool`.
    ///
    /// Each operation gives plain text, and `OperationTool` encodes it as a
    /// JSON string. This call decodes that string, thus the model reads the
    /// text itself. A corrective of the resolver is plain text already, and
    /// the call gives it as it is.
    ///
    /// - Parameter arguments: The payload of the model.
    /// - Returns: The plain-text answer of the operation, or a corrective
    ///   message.
    /// - Throws: The error of `OperationTool.call(arguments:)`.
    public func call(arguments: GeneratedContent) async throws -> String {
        // The body of a background call ends here, also when it added no run:
        // a corrective, a setup failure, or a payload that names no operation.
        defer {
            if let call = ToolContext.current {
                context.startedRuns.close(call: call.completionToken)
            }
        }
        let answer = try await operationTool.call(arguments: arguments)
        return (try? JSONDecoder().decode(String.self, from: Data(answer.utf8))) ?? answer
    }
}

extension AgentsTool: BackgroundTool {
    /// The mount of one call: the mount that the called operation declares
    /// on its `@Operation`.
    ///
    /// `start agent` is background, with no timeout, because a run can take
    /// any time. `list agents`, `find agents`, `check agent`, `cancel agent`,
    /// `send agent`, `send caller`, and an op that names no operation are
    /// synchronous.
    ///
    /// - Parameter arguments: The payload of the model.
    /// - Returns: The mount of the operation that `arguments` names.
    public func mount(for arguments: GeneratedContent) -> ToolMount? {
        operationTool.mount(for: arguments)
    }

    /// Gives the `next` sentence of the pending envelope of a call: the run
    /// works in the background, and the session injects its final message
    /// as a new message. The model does not call a tool to wait or to check.
    ///
    /// The sentence names the run by `completionToken`, the same token that
    /// the mail of the final message names the run by.
    ///
    /// - Parameter completionToken: The completion token of the call. The
    ///   `BackgroundTool` protocol gives it.
    /// - Returns: The sentence.
    public func collectInstruction(forCompletionToken completionToken: String) -> String {
        AgentsToolText.collectInstruction(forCompletionToken: completionToken)
    }

    /// Gives the canceler of the call `completionToken`: it cancels the run
    /// that the call started, or the run that the call starts later.
    ///
    /// When the call has a run, the canceler waits until the body of the call
    /// settled the call with its own terminal event, which holds the final
    /// message of the run ("… was cancelled."). The sweep of the run plane
    /// (`cancelAll()`, `close()`) runs the canceler and then keeps that
    /// terminal event. Without the wait, the sweep gives the call a terminal
    /// event with no final message. The sweep runs in the background, thus
    /// this wait does not delay `cancelAll()`. A call with no run yet has no
    /// body to wait for: the canceler returns at once.
    ///
    /// The Router asks for the canceler of each background call before the
    /// body of the call runs. Thus this call also opens the call in the record of the
    /// started runs: from now on, `check agent`, `cancel agent`, and
    /// `send agent` wait for the body to add its run, and do not answer that
    /// no run has the token.
    ///
    /// - Parameter completionToken: The completion token of the call.
    /// - Returns: The canceler. It reports ``OperationOutcome/cancelled``.
    public func canceler(
        forCompletionToken completionToken: String
    ) -> (@Sendable () async -> OperationOutcome)? {
        let startedRuns = context.startedRuns
        startedRuns.open(call: completionToken)
        return {
            if let call = startedRuns.cancelRun(ofCall: completionToken) {
                _ = await call.wait(completionToken: completionToken, seconds: nil)
            }
            return .cancelled
        }
    }
}

extension AgentsTool: CatalogNoticing {
    /// The board that each session that mounts the tool joins. A reload that
    /// changes the agents that the tool can start posts one notice on it.
    public var catalogNoticeBoard: CatalogNoticeBoard {
        notices.board
    }
}
