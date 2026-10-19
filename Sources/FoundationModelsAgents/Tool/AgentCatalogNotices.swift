import FoundationModelsExtras

/// Posts a catalog-change notice of the `agents` kind to each live session
/// that mounted one `agents` tool.
///
/// The description of the tool lists the agents that it can start, and it
/// does not change during a session: a change throws away the cached
/// prompt. Thus a reload that adds, removes, or changes the description of
/// such an agent reaches the model as a `CatalogChangeNotice`. A reload that
/// changes only a body, or only an agent that the tool cannot start, posts
/// nothing.
///
/// Each tool has its own board, because the agents that a tool can start
/// depend on its context (``AgentsToolContext/canStart(_:)``): the allowed
/// names, and the agent of the run. A session joins the board when
/// `ToolMounting.makeWrapped` mounts the tool, and leaves when its work
/// registry closes.
///
/// The init takes a reload stream that the caller subscribed to before it
/// read the catalog of the description. Thus no reload between the read and
/// the subscription is lost. One task follows the stream, and compares each
/// new catalog with the catalog that the session knows. The task holds the
/// stream, the board, and the context, and never `self`. The `deinit`
/// cancels it.
///
/// A reload that comes after the tool is made, but before a session mounts
/// it, reaches no session: the board has no session yet.
///
/// `final class ... Sendable`: each stored property is an immutable `let` of
/// a `Sendable` type, thus the class needs no lock.
final class AgentCatalogNotices: Sendable {
    /// The board that the sessions of the tool join.
    let board = CatalogNoticeBoard()

    /// The task that compares each catalog of the reload stream.
    private let following: Task<Void, Never>

    /// Starts to follow `reloads`.
    ///
    /// - Parameters:
    ///   - context: The context of the tool. It selects the agents that the
    ///     tool can start.
    ///   - known: The agents that the description of the tool lists.
    ///   - reloads: The reload stream of the registry, subscribed to before
    ///     `known` was read.
    init(context: AgentsToolContext, known: [AgentDefinition], reloads: AsyncStream<AgentCatalog>) {
        let board = board
        following = Task {
            var known = Self.entries(of: known)
            for await catalog in reloads {
                let current = Self.entries(of: catalog.definitions.filter(context.canStart))
                if let notice = CatalogChangeNotice(kind: .agents, from: known, to: current) {
                    await board.post(notice)
                }
                known = current
            }
        }
    }

    /// Cancels the task that follows the reloads.
    deinit {
        following.cancel()
    }

    /// Gives the catalog entry of each agent: its id, and its description on
    /// one line, as the full form of the description list shows it. An agent
    /// with no description gives `""`. The notices and
    /// ``AgentsTool/launchableAgents()`` use the same entries.
    ///
    /// - Parameter agents: The agents, in catalog order.
    /// - Returns: One entry for each agent, in catalog order.
    static func entries(of agents: [AgentDefinition]) -> [CatalogEntry] {
        agents.map { agent in
            CatalogEntry(name: agent.id, description: agent.description.map(AgentsToolDescription.oneLine) ?? "")
        }
    }
}
