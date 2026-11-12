import FoundationModels

/// The tools that an agent run can get, by name.
///
/// The catalog holds a factory for each name, not a tool. Each call of a
/// factory gives a new instance, thus each run gets its own tools. The
/// `tools` and `disallowedTools` keys of an agent select from these names.
///
/// ```swift
/// var tools = ToolCatalog()
/// tools.register("Read") { ReadTool(root: projectURL) }
/// ```
///
/// The host does not register `skills`: `AgentEnvironment.make` adds the
/// `skills` tool that it makes from the skills registry of the host.
///
/// A kept tool (``registerKept(_:vocabulary:_:)``) is in each run. Its factory
/// gets the definition of the run, thus the tool can filter its own
/// capabilities with the `tools` and `disallowedTools` keys of the agent.
public struct ToolCatalog: Sendable {
    /// Makes one new instance of a tool.
    public typealias Factory = @Sendable () -> any Tool

    /// Makes one new instance of a kept tool for the run of `definition`.
    public typealias KeptFactory = @Sendable (_ definition: AgentDefinition) -> any Tool

    /// Gives the capability names of a kept tool, for example `web`, `shell`,
    /// or `mcp__<server>__<tool>`.
    public typealias Vocabulary = @Sendable () -> [String]

    /// One kept tool: its capability names and its factory.
    private struct Kept: Sendable {
        /// Gives the capability names.
        let vocabulary: Vocabulary

        /// Makes the tool for one run.
        let factory: KeptFactory
    }

    /// The factory of each name.
    private var factories: [String: Factory] = [:]

    /// The kept tool of each name.
    private var keptTools: [String: Kept] = [:]

    /// The names of the catalog, in sorted order. The kept names are not
    /// here: ``keptNames`` gives them.
    public var names: [String] {
        factories.keys.sorted()
    }

    /// The names of the kept tools, in sorted order.
    public var keptNames: [String] {
        keptTools.keys.sorted()
    }

    /// Makes an empty catalog.
    public init() {}

    /// Adds a tool to the catalog.
    ///
    /// A second registration of the same name replaces the first.
    ///
    /// - Parameters:
    ///   - name: The name that the `tools` and `disallowedTools` keys use.
    ///   - factory: Makes one new instance of the tool for each call.
    public mutating func register(_ name: String, _ factory: @escaping Factory) {
        precondition(keptTools[name] == nil, "'\(name)' is a kept tool of the catalog")
        factories[name] = factory
    }

    /// Adds a kept tool to the catalog.
    ///
    /// Each run gets the tool: the `tools` and `disallowedTools` keys do not
    /// remove it. The resolution calls `factory` one time for each run, a new
    /// run and a restored run, with the definition of the run. Each name of
    /// `vocabulary`, and `name` itself, is a known name for the two keys, also
    /// for the MCP patterns, thus an entry such as `web` gives no warning. Such
    /// a name makes no tool: the kept tool reads the keys itself, for example
    /// with ``AgentDefinition/toolSelection(over:hasAgentsTool:)``.
    ///
    /// A second registration of the same name replaces the first. A kept name
    /// must not also be a name of ``register(_:_:)``.
    ///
    /// - Parameters:
    ///   - name: The name of the tool.
    ///   - vocabulary: Gives the capability names of the tool. The resolution
    ///     calls it for each run, thus the names can change.
    ///   - factory: Makes the tool for the run of one definition.
    public mutating func registerKept(
        _ name: String, vocabulary: @escaping Vocabulary, _ factory: @escaping KeptFactory
    ) {
        precondition(factories[name] == nil, "'\(name)' is a plain tool of the catalog")
        keptTools[name] = Kept(vocabulary: vocabulary, factory: factory)
    }

    /// The names that the kept tools make known: each kept name and each
    /// capability name.
    var keptVocabulary: [String] {
        keptTools.flatMap { name, kept in [name] + kept.vocabulary() }
    }

    /// Makes the kept tools for the run of `definition`, in name order.
    ///
    /// - Parameter definition: The agent of the run.
    /// - Returns: One new instance of each kept tool.
    func makeKeptTools(for definition: AgentDefinition) -> [any Tool] {
        keptNames.compactMap { name in keptTools[name]?.factory(definition) }
    }

    /// Makes a new instance of the tool with the name `name`.
    ///
    /// - Parameter name: A name of the catalog.
    /// - Returns: A new instance, or `nil` when the catalog does not hold the
    ///   name.
    func makeTool(named name: String) -> (any Tool)? {
        factories[name]?()
    }
}
