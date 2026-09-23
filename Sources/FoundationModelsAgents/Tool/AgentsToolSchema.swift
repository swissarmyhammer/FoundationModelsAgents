import FoundationModels
import Operations

/// Builds the fused schema of `AgentsTool`: the flat union of the
/// `Operations` runtime, with the `name` field made an enum of the agent
/// names (plan.md §9.1).
///
/// `SchemaFusion.fuse` of the `Operations` runtime gives each string field a
/// plain string schema. It does not read `ParamMeta.allowedValues`, and a
/// `ParamMeta` is static on its operation type, thus it cannot hold the names
/// of one catalog. This builder makes the same shape as that fusion: a
/// required `op` enum of each op string in operation order, then one optional
/// field for each parameter name, in the order of the first operation that
/// declares it and then by name. The one difference is the `name` field: here
/// it is an enum of the agent names.
///
/// The root schema has no description. The tool description holds the agent
/// list already, thus the list is not in the prompt two times.
enum AgentsToolSchema {
    /// The field that holds the name of the agent to start.
    private static let nameFieldName = "name"

    /// The description of the `op` field.
    private static let opFieldDescription = "The operation to perform, as \"verb noun\"."

    /// Builds the fused schema.
    ///
    /// - Parameters:
    ///   - name: The root type name: the tool name.
    ///   - operations: The operations of the tool, in tool order.
    ///   - agentNames: The names that the `name` field accepts. When it is
    ///     empty, the `name` field stays a plain string, because an empty
    ///     enum accepts no value.
    /// - Returns: The fused schema.
    /// - Throws: `GenerationSchema.SchemaError` when FoundationModels refuses
    ///   the schema.
    static func make(
        name: String, operations: [AnyOperation<AgentsToolContext>], agentNames: [String]
    ) throws -> GenerationSchema {
        let opField = DynamicGenerationSchema.Property(
            name: OperationKeys.opFieldName,
            description: opFieldDescription,
            schema: DynamicGenerationSchema(
                name: OperationKeys.opFieldName, description: opFieldDescription,
                anyOf: operations.map(\.opString)),
            isOptional: false)
        let fields = fieldUnion(of: operations).map { parameter in
            DynamicGenerationSchema.Property(
                name: parameter.name,
                description: parameter.description,
                schema: fieldSchema(for: parameter, agentNames: agentNames),
                isOptional: true)
        }
        let root = DynamicGenerationSchema(name: name, properties: [opField] + fields)
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// Gives one parameter for each parameter name in `operations`, in the
    /// order of the `Operations` fusion.
    ///
    /// - Parameter operations: The operations of the tool, in tool order.
    /// - Returns: The first declaration of each name, in the order of the
    ///   operation that declares it first, then by name.
    private static func fieldUnion(of operations: [AnyOperation<AgentsToolContext>]) -> [ParamMeta] {
        var seenNames: Set<String> = []
        return operations.flatMap { operation in
            operation.parameters
                .filter { seenNames.insert($0.name).inserted }
                .sorted { $0.name < $1.name }
        }
    }

    /// Gives the value schema of one field.
    ///
    /// - Parameters:
    ///   - parameter: The first declaration of the field.
    ///   - agentNames: The names that the `name` field accepts.
    /// - Returns: An enum of `agentNames` for a `name` field with names,
    ///   otherwise the schema of the parameter type.
    private static func fieldSchema(for parameter: ParamMeta, agentNames: [String]) -> DynamicGenerationSchema {
        guard parameter.name == nameFieldName, !agentNames.isEmpty else {
            return typeSchema(for: parameter.type)
        }
        return DynamicGenerationSchema(name: parameter.name, description: parameter.description, anyOf: agentNames)
    }

    /// Gives the value schema of one parameter type.
    ///
    /// - Parameter type: The parameter type.
    /// - Returns: The schema that FoundationModels uses for that type.
    private static func typeSchema(for type: ParamType) -> DynamicGenerationSchema {
        switch type {
        case .string:
            DynamicGenerationSchema(type: String.self)
        case .integer:
            DynamicGenerationSchema(type: Int.self)
        case .number:
            DynamicGenerationSchema(type: Double.self)
        case .boolean:
            DynamicGenerationSchema(type: Bool.self)
        case .array(let element):
            DynamicGenerationSchema(arrayOf: typeSchema(for: element))
        }
    }
}
