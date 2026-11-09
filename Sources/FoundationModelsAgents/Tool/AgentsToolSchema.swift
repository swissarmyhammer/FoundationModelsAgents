import FoundationModels
import Operations

/// Builds the fused schema of `AgentsTool`: the flat union of the
/// `Operations` runtime.
///
/// The shape is the same as `SchemaFusion.fuse` of the `Operations` runtime:
/// a required `op` enum of each op string in operation order, then one
/// optional field for each parameter name, in the order of the first
/// operation that declares it and then by name.
///
/// The `name` field is a plain string, not an enum of the agent names. An
/// enum is fixed when the tool is made, thus the model could not start an
/// agent that a reload adds. `start agent` checks the name against the live
/// catalog when the call runs, and gives the unknown-agent corrective for a
/// name that the catalog does not have.
///
/// The root schema has no description. The tool description holds the agent
/// list already, thus the list is not in the prompt two times.
enum AgentsToolSchema {
    /// The description of the `op` field.
    private static let opFieldDescription = "The operation to perform, as \"verb noun\"."

    /// Builds the fused schema.
    ///
    /// - Parameters:
    ///   - name: The root type name: the tool name.
    ///   - operations: The operations of the tool, in tool order.
    /// - Returns: The fused schema.
    /// - Throws: `GenerationSchema.SchemaError` when FoundationModels refuses
    ///   the schema.
    static func make(
        name: String, operations: [AnyOperation<AgentsToolContext>]
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
                schema: typeSchema(for: parameter.type, named: "\(name).\(parameter.name)"),
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

    /// Gives the value schema of one parameter type.
    ///
    /// An `.object` parameter is `anyOf` a string and an object with no
    /// properties, the same shape as `GraphQLArguments.generationSchema` of
    /// `FoundationModelsExtras`. Its encoded JSON Schema has no `type`, thus a
    /// host that checks the `type` of each argument lets a script send a plain
    /// object, and the model sends one JSON object in text.
    ///
    /// - Parameters:
    ///   - type: The parameter type.
    ///   - name: A name that is unique in the tool schema, such as
    ///     "<tool>.<parameter>". The named schemas of `.object` take it.
    /// - Returns: The schema that FoundationModels uses for that type.
    static func typeSchema(for type: ParamType, named name: String) -> DynamicGenerationSchema {
        switch type {
        case .string:
            DynamicGenerationSchema(type: String.self)
        case .integer:
            DynamicGenerationSchema(type: Int.self)
        case .number:
            DynamicGenerationSchema(type: Double.self)
        case .boolean:
            DynamicGenerationSchema(type: Bool.self)
        case .object:
            DynamicGenerationSchema(
                name: name,
                description: "one JSON object in text",
                anyOf: [
                    DynamicGenerationSchema(type: String.self),
                    DynamicGenerationSchema(name: "\(name).object", properties: []),
                ])
        case .array(let element):
            DynamicGenerationSchema(arrayOf: typeSchema(for: element, named: "\(name).element"))
        }
    }
}
