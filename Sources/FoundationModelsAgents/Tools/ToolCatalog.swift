import FoundationModels

/// The tools that an agent run can get, by name (plan.md §5).
///
/// The catalog holds a factory for each name, not a tool. Each call of a
/// factory gives a new instance, thus each run gets its own tools. The
/// `tools` and `disallowedTools` keys of an agent select from these names.
///
/// ```swift
/// var tools = ToolCatalog()
/// tools.register("skills") { skillsTool }
/// ```
public struct ToolCatalog: Sendable {
    /// Makes one new instance of a tool.
    public typealias Factory = @Sendable () -> any Tool

    /// The factory of each name.
    private var factories: [String: Factory] = [:]

    /// The names of the catalog, in sorted order.
    public var names: [String] {
        factories.keys.sorted()
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
        factories[name] = factory
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
