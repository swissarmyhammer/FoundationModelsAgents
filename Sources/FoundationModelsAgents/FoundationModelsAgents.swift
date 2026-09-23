/// The namespace root of the `FoundationModelsAgents` module.
///
/// The module finds Claude-style sub-agents (`agents/*.md`) in a dotfolder
/// stack and in marketplace plugins, and runs each agent in one Router
/// session. This enum declares no members. It holds the module documentation.
///
/// ## Layers (plan.md §3)
///
/// The layers are types in one library target, not separate modules.
///
/// - **Layer 1, `AgentDefinition`:** `AgentFrontmatter.decode` and the
///   validation of one located document.
/// - **Layer 2, `AgentRegistry`:** the cached catalog of `agents/*.md` over the
///   local layers and the marketplace layers. The file name is the id. The
///   registry makes the catalog again after a watch event or an update.
/// - **Layer 3, the FM adapter:** `AgentsTool` is one `OperationTool` with the
///   name "agents", four operations, and one noun. `AgentRunner` is an actor
///   that keeps the run limit, the run index, and the child runs. `AgentRun`
///   drives one `RoutedSession` and keeps its state and its result.
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
/// `FoundationModelsSkills` brings that module into the graph (plan.md §11).
public enum FoundationModelsAgents {}
