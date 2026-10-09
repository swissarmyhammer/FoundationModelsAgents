/// The namespace root of the `FoundationModelsAgents` module.
///
/// The module finds Claude-style sub-agents (`agents/<name>/AGENT.md`) in a
/// dotfolder stack and in marketplace plugins, and runs each agent in one
/// Router session. This enum declares no members. It holds the module
/// documentation.
///
/// ## Layers
///
/// The layers are types in one library target, not separate modules.
///
/// - **Layer 1, `AgentDefinition`:** `AgentFrontmatter.decode` and the
///   validation of one located document.
/// - **Layer 2, `AgentRegistry`:** the cached catalog of
///   `agents/<name>/AGENT.md` over the local layers and the marketplace
///   layers. The folder name is the id. The registry makes the catalog again
///   after a watch event or an update.
/// - **Layer 3, the FM adapter:** `AgentsTool` is one `OperationTool` with the
///   name "agents" and six operations: `list agents`, `start agent`,
///   `check agent`, `cancel agent`, `send agent`, and `send caller`.
///   `AgentRunner` is an actor that keeps the run limit, the run index, and
///   the child runs. `AgentRun` drives one `RoutedSession` and keeps its
///   state and its result. A run and its caller can send messages to each
///   other while the run works, and the run gives one final message when it
///   ends.
///
/// Layers 1 and 2 use no model. They keep the `model` key as text, and the
/// runner matches it to a slot.
///
/// ## The sibling packages
///
/// - `FoundationModelsExtras`: `DotfolderStack`, `FrontmatterDocumentStack`,
///   `DotfolderWatcher`, `StenciledDotfolderStack`, `QuarantinedText`,
///   `AgentsMd`, `SlashCommand`, `SlashCommandProviding`, and the
///   `Operations` module (`OperationTool`, `@Operation`, `OperationResolver`).
/// - `Marketplace`: `MarketplaceLayerProviding`, `MarketplaceLayer`, and
///   `MarketplaceStore`.
/// - `FoundationModelsRouter`: the `LanguageModelProfile` slots,
///   `RoutedSession`, `ToolContext`, and the recording.
/// - `FoundationModelsSkills`: `SkillsRegistry`.
///
/// The host makes the dependencies: the `DotfolderStack`, the
/// `MarketplaceStore`, the `Router` and its resolved `LanguageModelProfile`,
/// and the `SkillsRegistry`. The host session and the sub-agents use the same
/// instances.
///
/// The name `AgentSession` is not a type of this module.
/// `FoundationModelsMetadataRegistry` declares a protocol with that name, and
/// `FoundationModelsSkills` brings that module into the graph.
public enum FoundationModelsAgents {}
